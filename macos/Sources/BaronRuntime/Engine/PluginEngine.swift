import Foundation

/// Where one plugin's code runs: a JavaScriptCore context in Baron's process (stage 1, `JSCEngineContext`) or
/// in the sandboxed helper (stage 2, `HelperEngine`). The runtime sees no difference; the envelopes are the same.
/// Design: docs/design/plugin-platform/02-runtime.md
public protocol PluginEngine: AnyObject, Sendable {
    /// Installs `__baronNative`; `send` gets every envelope the plugin sends.
    func installNative(send: @escaping @Sendable (String) -> Void) async throws
    /// Evaluates a script and returns its result as a string; an exception becomes `JSCEngineContext.EngineError`.
    @discardableResult
    func evaluate(_ script: String, sourceURL: String) async throws -> String?
    /// Hands one envelope to the prelude's `__baronReceive`.
    func deliver(_ json: String)
    /// Drops the context; later calls fail with `unloaded`.
    func unload()
    /// How long the current synchronous run of plugin code has lasted, or nil when none is running.
    func busyDuration() async -> Duration?
    /// Gives up on a context stuck in synchronous code. In Baron's process its thread can't be stopped and is
    /// abandoned; the helper is restarted instead.
    func abandon()
    /// Called when the context is lost with its process (the helper crashed or was restarted).
    var onLost: (@Sendable () -> Void)? { get set }
}

extension JSCEngineContext: PluginEngine {
    public func busyDuration() async -> Duration? { busyFor }
    public func abandon() { unload() }
    public var onLost: (@Sendable () -> Void)? {
        get { nil }
        set {} // A context in Baron's process goes only with Baron.
    }
}
