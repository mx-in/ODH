import BaronCore
import Foundation

/// Runs plugins in-process (stage 1): one JavaScriptCore context per plugin, loaded on first need.
/// Design: docs/design/plugin-platform/02-runtime.md
public actor PluginRuntime {
    public let limits: RuntimeLimits
    private let handler: HostCallHandler
    private var plugins: [String: RuntimePlugin] = [:]
    private var instances: [String: PluginInstance] = [:]
    private var states: [String: PluginRuntimeState] = [:]

    public init(handler: HostCallHandler, limits: RuntimeLimits = RuntimeLimits()) {
        self.handler = handler
        self.limits = limits
    }

    public func register(_ plugin: RuntimePlugin) {
        plugins[plugin.id] = plugin
        states[plugin.id] = .unloaded
    }

    public func state(of pluginID: String) -> PluginRuntimeState {
        states[pluginID] ?? .unloaded
    }

    /// Loads the plugin's context if it isn't loaded; returns the resulting state.
    @discardableResult
    public func load(_ pluginID: String) async -> PluginRuntimeState {
        _ = await instance(for: pluginID)
        return state(of: pluginID)
    }

    /// Runs one of the plugin's exports, loading the plugin first if needed. Gives up with `timeout` after the
    /// target's limit and tells the plugin through its signal.
    public func dispatch(_ pluginID: String, _ target: DispatchTarget, name: String, payload: DispatchPayload) async -> Result<JSONValue, HostError> {
        let instance: PluginInstance
        switch await self.instance(for: pluginID) {
        case .success(let loaded): instance = loaded
        case .failure(let error): return .failure(error)
        }
        let json = payload.json(pluginVersion: instance.plugin.manifest.version)
        return await instance.dispatch(target, name: name, payload: json, limit: limits.timeLimit(for: target))
    }

    func instance(for pluginID: String) async -> Result<PluginInstance, HostError> {
        guard let plugin = plugins[pluginID] else { return .failure(.notFound("No plugin \(pluginID)")) }
        switch state(of: pluginID) {
        case .broken(let reason), .suspended(let reason): return .failure(.unavailable(reason))
        case .ready: if let instance = instances[pluginID] { return .success(instance) }
        case .unloaded: break
        }
        let instance = PluginInstance(plugin: plugin, handler: handler)
        do {
            let bundle = try plugin.bundleSource()
            try await withLimit(limits.load, "Its code took longer than \(limits.load) to load") {
                try await instance.load(bundle: bundle)
            }
            instances[pluginID] = instance
            states[pluginID] = .ready
            return .success(instance)
        } catch {
            instance.engine.unload()
            let reason = (error as? HostError)?.message ?? "\(error)"
            states[pluginID] = .broken(reason)
            return .failure(.unavailable(reason))
        }
    }

    /// Runs `body`, giving up after `limit` without waiting for it. Plugin code can't be interrupted,
    /// so a body that never returns leaves its context abandoned.
    private func withLimit(_ limit: Duration, _ message: String, _ body: @escaping @Sendable () async throws -> Void) async throws {
        try await withRace(limit, timeout: HostError.timeout(message), body)
    }
}
