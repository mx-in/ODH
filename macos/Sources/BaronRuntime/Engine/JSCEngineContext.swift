import Foundation
import JavaScriptCore

/// One plugin's JavaScript context: its own virtual machine (so objects can't cross plugins and each has its own heap)
/// and its own serial queue, which every touch of the context goes through. A slow plugin never blocks another, or Baron.
public final class JSCEngineContext: @unchecked Sendable {
    public let pluginID: String
    let queue: DispatchQueue
    private var virtualMachine: JSVirtualMachine?
    private var context: JSContext?

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

    public init(pluginID: String) {
        self.pluginID = pluginID
        queue = DispatchQueue(label: "org.odh.baron.plugin.\(pluginID)", qos: .userInitiated)
        queue.sync {
            let virtualMachine = JSVirtualMachine()!
            let context = JSContext(virtualMachine: virtualMachine)!
            context.name = pluginID
            self.virtualMachine = virtualMachine
            self.context = context
        }
    }

    /// Runs `body` with the context on the plugin's queue.
    func withContext<T: Sendable>(_ body: @escaping @Sendable (JSContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let context = self.context else { return continuation.resume(throwing: EngineError.unloaded) }
                continuation.resume(with: Result { try body(context) })
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

    /// Drops the context and its virtual machine; later calls fail with `unloaded`.
    public func unload() {
        queue.async {
            self.context = nil
            self.virtualMachine = nil
        }
    }

    static func describe(_ exception: JSValue) -> String {
        let message = exception.toString() ?? "Unknown error"
        guard let line = exception.objectForKeyedSubscript("line"), !line.isUndefined else { return message }
        return "\(message) (line \(line.toInt32()))"
    }
}
