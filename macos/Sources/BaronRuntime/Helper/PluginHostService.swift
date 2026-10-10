import Darwin
import Foundation

/// The helper's side of the connection: one JavaScriptCore context per id, each with its own virtual machine
/// and queue, sending envelopes back to Baron. Runs in `BaronPluginHost.xpc`, and in-process in tests.
public final class PluginHostService: NSObject, PluginHostXPC, @unchecked Sendable {
    private let client: PluginHostClientXPC
    private let lock = NSLock()
    private var contexts: [String: JSCEngineContext] = [:]

    init(client: PluginHostClientXPC) {
        self.client = client
    }

    private func context(_ id: String) -> JSCEngineContext? {
        lock.withLock { contexts[id] }
    }

    public func createContext(_ id: String, pluginID: String, inspectable: Bool, reply: @escaping (String?) -> Void) {
        let engine = JSCEngineContext(pluginID: pluginID, inspectable: inspectable)
        lock.withLock { contexts[id] = engine }
        let client = AnySendable(self.client), reply = AnySendable(reply)
        Task {
            do {
                try await engine.installNative(send: { json in client.value.send(id, json: json) })
                reply.value(nil)
            } catch {
                reply.value("\(error)")
            }
        }
    }

    public func evaluate(_ id: String, script: String, sourceURL: String, reply: @escaping (String?, Int, String?) -> Void) {
        guard let engine = context(id) else { return reply(nil, 2, nil) }
        let reply = AnySendable(reply)
        Task {
            do {
                reply.value(try await engine.evaluate(script, sourceURL: sourceURL), 0, nil)
            } catch JSCEngineContext.EngineError.exception(let message) {
                reply.value(nil, 1, message)
            } catch {
                reply.value(nil, 2, nil)
            }
        }
    }

    public func deliver(_ id: String, json: String) {
        context(id)?.deliver(json)
    }

    public func unload(_ id: String) {
        lock.withLock { contexts.removeValue(forKey: id) }?.unload()
    }

    public func busy(_ id: String, reply: @escaping (Double) -> Void) {
        let busy = context(id)?.busyFor
        reply(busy.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? -1)
    }

    public func memoryFootprint(reply: @escaping (UInt64) -> Void) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        reply(result == KERN_SUCCESS ? info.phys_footprint : 0)
    }
}

/// XPC proxies and reply blocks may be used from any thread.
struct AnySendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Accepts Baron's connection in the helper: `NSXPCListener.service()` there, an anonymous listener in tests.
public final class PluginHostListener: NSObject, NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = PluginHostInterfaces.host
        connection.remoteObjectInterface = PluginHostInterfaces.client
        guard let client = connection.remoteObjectProxy as? PluginHostClientXPC else { return false }
        connection.exportedObject = PluginHostService(client: client)
        connection.resume()
        return true
    }
}
