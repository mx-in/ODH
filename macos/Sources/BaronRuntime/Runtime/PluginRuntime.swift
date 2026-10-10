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
    private var strikes: [String: [ContinuousClock.Instant]] = [:]
    private var watchdog: Task<Void, Never>?
    private var lastUsed: [String: ContinuousClock.Instant] = [:]

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
        lastUsed[pluginID] = .now
        let result = await instance.dispatch(target, name: name, payload: json, limit: limits.timeLimit(for: target))
        lastUsed[pluginID] = .now
        if result.failure?.code == "timeout", instances[pluginID] === instance { strike(pluginID) }
        return result
    }

    /// Drops the plugin's context so the next dispatch loads it fresh: after an update, a preference change
    /// or a `baron dev` rebuild. Waiting dispatches fail with `unavailable`.
    public func reload(_ pluginID: String) {
        guard let instance = instances.removeValue(forKey: pluginID) else { return }
        instance.failAll(.unavailable("The plugin was reloaded"))
        instance.engine.unload()
        if state(of: pluginID) == .ready { states[pluginID] = .unloaded }
    }

    /// Whether the plugin's context is loaded now.
    public func isLoaded(_ pluginID: String) -> Bool {
        instances[pluginID] != nil
    }

    /// Lets a suspended plugin run again, in a fresh context.
    public func reenable(_ pluginID: String) {
        guard case .suspended = state(of: pluginID) else { return }
        strikes[pluginID] = nil
        states[pluginID] = .unloaded
    }

    /// Counts a dispatch that ran out of time; too many in the window suspends the plugin.
    private func strike(_ pluginID: String) {
        let now = ContinuousClock.now
        let recent = (strikes[pluginID] ?? []).filter { now - $0 < limits.strikeWindow } + [now]
        strikes[pluginID] = recent
        if recent.count >= limits.strikes {
            suspend(pluginID, "It ran out of time \(recent.count) times in \(limits.strikeWindow); re-enable it to try again")
        }
    }

    private func suspend(_ pluginID: String, _ reason: String) {
        states[pluginID] = .suspended(reason)
        guard let instance = instances.removeValue(forKey: pluginID) else { return }
        instance.failAll(.unavailable(reason))
        instance.engine.unload()
    }

    /// Suspends plugins stuck in synchronous code. Their thread can't be stopped (stage 1), so the context is abandoned.
    private func checkForStuckPlugins() {
        let now = ContinuousClock.now
        for (pluginID, instance) in instances {
            if let busy = instance.engine.busyFor, busy > limits.stuck {
                suspend(pluginID, "It stopped responding (stuck for more than \(limits.stuck)); re-enable it to try again")
            } else if instance.pendingDispatches == 0, instance.engine.busyFor == nil, now - (lastUsed[pluginID] ?? now) > limits.idle {
                reload(pluginID)
            }
        }
        if instances.isEmpty {
            watchdog?.cancel()
            watchdog = nil
        }
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let interval = limits.stuck / 4
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.checkForStuckPlugins()
            }
        }
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
            lastUsed[pluginID] = .now
            startWatchdog()
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
