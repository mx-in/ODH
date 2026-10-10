import Darwin
import Foundation

/// Baron's side of the sandboxed helper: one connection shared by every plugin's `HelperEngine`. When the helper
/// goes away (a crash, or a restart for a stuck plugin or too much memory), every engine is told, and the next
/// need starts it again. Design: docs/design/plugin-platform/02-runtime.md#stage-2-the-sandboxed-helper
public final class PluginHost: NSObject, PluginHostClientXPC, @unchecked Sendable {
    public static let serviceName = "org.odh.baron.plugin-host"
    /// The helper is restarted above this footprint.
    public static let memoryLimit: UInt64 = 512 * 1024 * 1024

    private let connect: () -> NSXPCConnection
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var engines: [String: HelperEngine] = [:]
    private var watchdog: Task<Void, Never>?
    private let memoryLimit: UInt64

    public init(serviceName: String = PluginHost.serviceName, memoryLimit: UInt64 = PluginHost.memoryLimit) {
        connect = { NSXPCConnection(serviceName: serviceName) }
        self.memoryLimit = memoryLimit
    }

    /// For tests: a helper behind an anonymous listener in this process.
    public init(endpoint: NSXPCListenerEndpoint, memoryLimit: UInt64 = PluginHost.memoryLimit) {
        connect = { NSXPCConnection(listenerEndpoint: endpoint) }
        self.memoryLimit = memoryLimit
    }

    /// An engine factory for `PluginRuntime`.
    public var engineFactory: PluginRuntime.EngineFactory {
        { [self] plugin in HelperEngine(host: self, pluginID: plugin.id, inspectable: plugin.development) }
    }

    // MARK: Engines

    func register(_ engine: HelperEngine) {
        lock.withLock { engines[engine.id] = engine }
        startWatchdog()
    }

    func unregister(_ id: String) {
        lock.withLock { _ = engines.removeValue(forKey: id) }
    }

    public func send(_ id: String, json: String) {
        lock.withLock { engines[id] }?.received(json)
    }

    // MARK: The connection

    /// The helper's proxy, connecting (and so launching the helper) when needed. `failed` runs instead of the
    /// reply when the message can't be delivered.
    func proxy(failed: @escaping @Sendable (Error) -> Void) -> PluginHostXPC? {
        lock.withLock {
            if connection == nil {
                let fresh = connect()
                fresh.remoteObjectInterface = PluginHostInterfaces.host
                fresh.exportedInterface = PluginHostInterfaces.client
                fresh.exportedObject = self
                fresh.interruptionHandler = { [weak self, weak fresh] in fresh.map { self?.lost($0) } }
                fresh.invalidationHandler = { [weak self, weak fresh] in fresh.map { self?.lost($0) } }
                fresh.resume()
                connection = fresh
            }
            return connection?.remoteObjectProxyWithErrorHandler(failed) as? PluginHostXPC
        }
    }

    /// The helper went away: drop the connection and tell every engine that its context went with it.
    private func lost(_ gone: NSXPCConnection) {
        let affected: [HelperEngine] = lock.withLock {
            guard connection === gone else { return [] }
            connection = nil
            defer { engines.removeAll() }
            return Array(engines.values)
        }
        gone.invalidate()
        affected.forEach { $0.lost() }
    }

    /// Stops the helper, for a plugin stuck in synchronous code or a helper using too much memory. Every
    /// plugin's context goes with it; each loads again on its next need.
    public func restart() {
        guard let current = lock.withLock({ connection }) else { return }
        let pid = current.processIdentifier
        // A helper in this process (tests) only loses its connection.
        if pid > 0, pid != getpid() { kill(pid, SIGKILL) }
        lost(current)
    }

    private func startWatchdog() {
        lock.withLock {
            guard watchdog == nil else { return }
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard let self else { return }
                    await self.checkMemory()
                }
            }
        }
    }

    /// Restarts the helper when it uses more than its memory limit; the watchdog checks every 10 seconds.
    public func checkMemory() async {
        if await footprint() > memoryLimit { restart() }
    }

    /// The helper's memory footprint in bytes; 0 when it isn't running.
    public func footprint() async -> UInt64 {
        guard lock.withLock({ connection != nil }) else { return 0 }
        return await withCheckedContinuation { continuation in
            let once = OnceFlag()
            guard let proxy = proxy(failed: { _ in if once.claim() { continuation.resume(returning: 0) } }) else {
                return continuation.resume(returning: 0)
            }
            proxy.memoryFootprint { bytes in if once.claim() { continuation.resume(returning: bytes) } }
        }
    }
}

/// Lets exactly one of a reply and an error handler resume a continuation.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}

/// A plugin's context in the helper, driven over `PluginHost`'s connection.
final class HelperEngine: PluginEngine, @unchecked Sendable {
    let id = UUID().uuidString
    private let pluginID: String
    private let inspectable: Bool
    private weak var host: PluginHost?
    private let lock = NSLock()
    private var send: (@Sendable (String) -> Void)?
    private var lostHandler: (@Sendable () -> Void)?
    private var gone = false

    init(host: PluginHost, pluginID: String, inspectable: Bool) {
        self.host = host
        self.pluginID = pluginID
        self.inspectable = inspectable
    }

    var onLost: (@Sendable () -> Void)? {
        get { lock.withLock { lostHandler } }
        set { lock.withLock { lostHandler = newValue } }
    }

    func installNative(send: @escaping @Sendable (String) -> Void) async throws {
        guard let host else { throw JSCEngineContext.EngineError.unloaded }
        lock.withLock { self.send = send }
        host.register(self)
        let message: String? = try await call { proxy, done in proxy.createContext(self.id, pluginID: self.pluginID, inspectable: self.inspectable, reply: done) }
        if let message { throw JSCEngineContext.EngineError.exception(message) }
    }

    func evaluate(_ script: String, sourceURL: String) async throws -> String? {
        let (value, kind, message): (String?, Int, String?) = try await call { proxy, done in
            proxy.evaluate(self.id, script: script, sourceURL: sourceURL) { done(($0, $1, $2)) }
        }
        switch kind {
        case 0: return value
        case 1: throw JSCEngineContext.EngineError.exception(message ?? "Unknown error")
        default: throw JSCEngineContext.EngineError.unloaded
        }
    }

    func deliver(_ json: String) {
        host?.proxy(failed: { _ in })?.deliver(id, json: json)
    }

    func unload() {
        host?.unregister(id)
        host?.proxy(failed: { _ in })?.unload(id)
    }

    func busyDuration() async -> Duration? {
        let seconds: Double? = try? await call { proxy, done in proxy.busy(self.id, reply: done) }
        guard let seconds, seconds >= 0 else { return nil }
        return .milliseconds(Int(seconds * 1000))
    }

    func abandon() {
        host?.restart()
    }

    func received(_ json: String) {
        lock.withLock { send }?(json)
    }

    func lost() {
        let handler: (@Sendable () -> Void)? = lock.withLock {
            guard !gone else { return nil }
            gone = true
            return lostHandler
        }
        handler?()
    }

    /// Sends one message with a reply; fails with `unloaded` when the helper can't be reached or goes away.
    private func call<T: Sendable>(_ body: @escaping (PluginHostXPC, @escaping (T) -> Void) -> Void) async throws -> T {
        guard let host, !lock.withLock({ gone }) else { throw JSCEngineContext.EngineError.unloaded }
        return try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            guard let proxy = host.proxy(failed: { _ in if once.claim() { continuation.resume(throwing: JSCEngineContext.EngineError.unloaded) } }) else {
                return continuation.resume(throwing: JSCEngineContext.EngineError.unloaded)
            }
            body(proxy) { value in if once.claim() { continuation.resume(returning: value) } }
        }
    }
}
