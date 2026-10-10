import CryptoKit
import Foundation
import JavaScriptCore
import Security

/// One plugin's JavaScript context: its own virtual machine (so objects can't cross plugins and each has its own heap)
/// and its own serial queue, which every touch of the context goes through. A slow plugin never blocks another, or Baron.
public final class JSCEngineContext: @unchecked Sendable {
    public let pluginID: String
    let queue: DispatchQueue
    private var virtualMachine: JSVirtualMachine?
    private var context: JSContext?
    private let busyLock = NSLock()
    private var busySince: ContinuousClock.Instant?
    /// Pending timers by the prelude's id; only touched on `queue`.
    private var timers: [Int: DispatchWorkItem] = [:]

    public enum EngineError: Error, Equatable, CustomStringConvertible {
        case exception(String)
        case unloaded

        public var description: String {
            switch self {
            case .exception(let message): message
            case .unloaded: "The plugin's context was unloaded"
            }
        }
    }

    public init(pluginID: String, inspectable: Bool = false) {
        self.pluginID = pluginID
        queue = DispatchQueue(label: "org.odh.baron.plugin.\(pluginID)", qos: .userInitiated)
        queue.sync {
            let virtualMachine = JSVirtualMachine()!
            let context = JSContext(virtualMachine: virtualMachine)!
            context.name = pluginID
            context.isInspectable = inspectable
            self.virtualMachine = virtualMachine
            self.context = context
        }
    }

    /// Runs `body` with the context on the plugin's queue.
    func withContext<T: Sendable>(_ body: @escaping @Sendable (JSContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let context = self.context else { return continuation.resume(throwing: EngineError.unloaded) }
                continuation.resume(with: self.running { Result { try body(context) } })
            }
        }
    }

    /// Evaluates a script and returns its result as a string (for tests and loading); a thrown exception becomes an error.
    @discardableResult
    public func evaluate(_ script: String, sourceURL: String = "plugin.js") async throws -> String? {
        try await withContext { context in
            context.exception = nil
            let value = context.evaluateScript(script, withSourceURL: URL(string: sourceURL))
            if let exception = context.exception {
                context.exception = nil
                throw EngineError.exception(Self.describe(exception))
            }
            return value.flatMap { $0.isUndefined ? nil : $0.toString() }
        }
    }

    /// Installs `__baronNative`, the only door the prelude has out of the context. `send` gets every envelope
    /// the plugin sends; it is called on the plugin's queue.
    public func installNative(send: @escaping @Sendable (String) -> Void) async throws {
        try await withContext { context in
            let native = JSValue(newObjectIn: context)!
            let sendBlock: @convention(block) (String) -> Void = { json in send(json) }
            native.setObject(sendBlock, forKeyedSubscript: "send" as NSString)
            let setTimer: @convention(block) (Int, Double) -> Void = { [weak self] id, ms in self?.setTimer(id: id, milliseconds: ms) }
            let clearTimer: @convention(block) (Int) -> Void = { [weak self] id in self?.timers.removeValue(forKey: id)?.cancel() }
            native.setObject(setTimer, forKeyedSubscript: "setTimer" as NSString)
            native.setObject(clearTimer, forKeyedSubscript: "clearTimer" as NSString)
            let randomBytes: @convention(block) (Int) -> [Int] = { count in Self.randomBytes(count) }
            let digest: @convention(block) (String, String) -> String = { algorithm, base64 in Self.digest(algorithm, base64) ?? "" }
            native.setObject(randomBytes, forKeyedSubscript: "randomBytes" as NSString)
            native.setObject(digest, forKeyedSubscript: "digest" as NSString)
            context.setObject(native, forKeyedSubscript: "__baronNative" as NSString)
        }
    }

    /// Called on `queue` by the prelude; fires `__baronFireTimer(id)` on the same queue.
    private func setTimer(id: Int, milliseconds: Double) {
        timers.removeValue(forKey: id)?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.timers.removeValue(forKey: id) != nil, let context = self.context else { return }
            self.running {
                context.exception = nil
                context.objectForKeyedSubscript("__baronFireTimer")?.call(withArguments: [id])
                context.exception = nil
            }
        }
        timers[id] = item
        queue.asyncAfter(deadline: .now() + .milliseconds(Int(max(0, milliseconds).rounded())), execute: item)
    }

    /// Marks the time spent inside plugin code, so a watchdog can tell a stuck plugin.
    private func running<T>(_ body: () -> T) -> T {
        busyLock.withLock { busySince = ContinuousClock.now }
        defer { busyLock.withLock { busySince = nil } }
        return body()
    }

    /// How long the current synchronous run of plugin code has lasted, or nil when none is running.
    public var busyFor: Duration? {
        busyLock.withLock { busySince.map { ContinuousClock.now - $0 } }
    }

    /// Timers waiting to fire.
    public var pendingTimerCount: Int {
        queue.sync { timers.count }
    }

    /// Hands one envelope to the prelude's `__baronReceive`, on the plugin's queue.
    public func deliver(_ json: String) {
        queue.async {
            guard let context = self.context else { return }
            self.running {
                context.exception = nil
                context.objectForKeyedSubscript("__baronReceive")?.call(withArguments: [json])
                context.exception = nil
            }
        }
    }

    /// Drops the context and its virtual machine; later calls fail with `unloaded`.
    public func unload() {
        queue.async {
            self.timers.values.forEach { $0.cancel() }
            self.timers.removeAll()
            self.context = nil
            self.virtualMachine = nil
        }
    }

    static func randomBytes(_ count: Int) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: max(0, min(count, 65536)))
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { fatalError("SecRandomCopyBytes failed") }
        return bytes.map(Int.init)
    }

    /// SHA digests for `crypto.subtle.digest`; nil for an unknown algorithm or bad base64.
    static func digest(_ algorithm: String, _ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let digest: any Sequence<UInt8>
        switch algorithm {
        case "SHA-1": digest = Insecure.SHA1.hash(data: data)
        case "SHA-256": digest = SHA256.hash(data: data)
        case "SHA-384": digest = SHA384.hash(data: data)
        case "SHA-512": digest = SHA512.hash(data: data)
        default: return nil
        }
        return Data(digest).base64EncodedString()
    }

    static func describe(_ exception: JSValue) -> String {
        let message = exception.toString() ?? "Unknown error"
        guard let line = exception.objectForKeyedSubscript("line"), !line.isUndefined else { return message }
        return "\(message) (line \(line.toInt32()))"
    }
}
