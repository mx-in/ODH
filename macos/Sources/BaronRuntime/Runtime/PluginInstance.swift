import BaronCore
import Foundation

/// One plugin's live context: loads it, relays its calls to the host, and matches dispatch results.
final class PluginInstance: @unchecked Sendable {
    let plugin: RuntimePlugin
    let engine: JSCEngineContext
    private let handler: HostCallHandler
    private let lock = NSLock()
    private var nextDispatchID = 1
    private var waiting: [Int: CheckedContinuation<Result<JSONValue, HostError>, Never>] = [:]

    init(plugin: RuntimePlugin, handler: HostCallHandler) {
        self.plugin = plugin
        self.handler = handler
        engine = JSCEngineContext(pluginID: plugin.id)
    }

    /// Evaluates the prelude and the plugin's bundle, and checks that the bundle defined actions.
    func load(bundle: String) async throws {
        try await engine.installNative(send: { [weak self] json in self?.received(json) })
        try await engine.evaluate(Prelude.source, sourceURL: "baron-prelude.js")
        do {
            try await engine.evaluate(bundle, sourceURL: plugin.manifest.main)
        } catch let error as JSCEngineContext.EngineError {
            throw HostError("plugin_error", "Its code threw while loading: \(error)")
        }
        let defined = try await engine.evaluate("typeof globalThis.__baronPlugin === 'object' && globalThis.__baronPlugin !== null && typeof globalThis.__baronPlugin.actions === 'object'")
        guard defined == "true" else {
            throw HostError("plugin_error", "Its bundle defines no actions; export default definePlugin({ actions: … })")
        }
    }

    private func received(_ json: String) {
        switch OutboundEnvelope(json: json) {
        case .call(let call)?:
            Task {
                let result = await handler.handle(call, from: plugin)
                engine.deliver(InboundEnvelope.result(id: call.id, result).json)
            }
        case .result(let id, let result)?:
            let continuation = lock.withLock { waiting.removeValue(forKey: id) }
            continuation?.resume(returning: result)
        case nil:
            break
        }
    }

    /// Sends a dispatch and waits for its result; `limit` bounds the wait.
    func dispatch(_ target: DispatchTarget, name: String, payload: JSONValue, limit: Duration) async -> Result<JSONValue, HostError> {
        let id = lock.withLock { () -> Int in
            defer { nextDispatchID += 1 }
            return nextDispatchID
        }
        let timer = Task { [weak self] in
            try await Task.sleep(for: limit)
            self?.finish(id, with: .failure(.timeout("The plugin took longer than \(limit) to answer")))
            self?.engine.deliver(InboundEnvelope.cancel(id: id).json)
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            lock.withLock { waiting[id] = continuation }
            engine.deliver(InboundEnvelope.dispatch(id: id, target: target, name: name, payload: payload).json)
        }
    }

    private func finish(_ id: Int, with result: Result<JSONValue, HostError>) {
        lock.withLock { waiting.removeValue(forKey: id) }?.resume(returning: result)
    }

    var pendingDispatches: Int { lock.withLock { waiting.count } }

    /// Fails every waiting dispatch, for example when the plugin is suspended.
    func failAll(_ error: HostError) {
        let all = lock.withLock { () -> [CheckedContinuation<Result<JSONValue, HostError>, Never>] in
            defer { waiting.removeAll() }
            return Array(waiting.values)
        }
        all.forEach { $0.resume(returning: .failure(error)) }
    }
}
