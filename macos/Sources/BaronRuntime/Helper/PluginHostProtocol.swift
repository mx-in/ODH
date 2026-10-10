import Foundation

/// What Baron asks of the sandboxed helper (`BaronPluginHost.xpc`). Each context has an id Baron picks; the
/// helper reads no files, so the prelude and bundles arrive as `evaluate` scripts.
/// Design: docs/design/plugin-platform/02-runtime.md#stage-2-the-sandboxed-helper
@objc public protocol PluginHostXPC {
    /// Makes a JavaScriptCore context with `__baronNative`; replies with an error message, or nil.
    func createContext(_ id: String, pluginID: String, inspectable: Bool, reply: @escaping (String?) -> Void)
    /// Replies with the result, and an error kind (0 none, 1 exception, 2 unloaded) with its message.
    func evaluate(_ id: String, script: String, sourceURL: String, reply: @escaping (String?, Int, String?) -> Void)
    /// Hands an envelope to the context's `__baronReceive`.
    func deliver(_ id: String, json: String)
    func unload(_ id: String)
    /// Seconds the context has been running synchronous code, or a negative number when it isn't.
    func busy(_ id: String, reply: @escaping (Double) -> Void)
    /// The helper's memory footprint in bytes.
    func memoryFootprint(reply: @escaping (UInt64) -> Void)
}

/// What the helper sends back: the envelopes plugin code sends through `__baronNative.send`.
@objc public protocol PluginHostClientXPC {
    func send(_ id: String, json: String)
}

enum PluginHostInterfaces {
    static var host: NSXPCInterface { NSXPCInterface(with: PluginHostXPC.self) }
    static var client: NSXPCInterface { NSXPCInterface(with: PluginHostClientXPC.self) }
}
