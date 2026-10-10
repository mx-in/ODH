import BaronCore
import Foundation

/// The envelopes from `@baron/api`'s envelope.ts, as Swift sees them. Design: 03-host-api-and-ipc.md#messages
public struct HostCall: Equatable, Sendable {
    public var id: Int
    public var namespace: String
    public var method: String
    public var arguments: [JSONValue]

    public init(id: Int, namespace: String, method: String, arguments: [JSONValue]) {
        self.id = id
        self.namespace = namespace
        self.method = method
        self.arguments = arguments
    }
}

/// A failed call or dispatch. `code` is one of the design's error codes, or `plugin_error`.
public struct HostError: Error, Equatable, Sendable, CustomStringConvertible {
    public var code: String
    public var message: String
    public var data: JSONValue?
    public var stack: String?

    public init(_ code: String, _ message: String, data: JSONValue? = nil, stack: String? = nil) {
        self.code = code
        self.message = message
        self.data = data
        self.stack = stack
    }

    public var description: String { "\(code): \(message)" }

    public static func invalidArgument(_ message: String) -> HostError { HostError("invalid_argument", message) }
    public static func notFound(_ message: String) -> HostError { HostError("not_found", message) }
    public static func timeout(_ message: String) -> HostError { HostError("timeout", message) }
    public static func unavailable(_ message: String) -> HostError { HostError("unavailable", message) }
    public static func internalError(_ message: String) -> HostError { HostError("internal", message) }
}

/// What a plugin's context sends: calls for the host, and results of Baron's dispatches.
enum OutboundEnvelope {
    case call(HostCall)
    case result(id: Int, Result<JSONValue, HostError>)

    init?(json: String) {
        guard let value = try? JSONValue(data: Data(json.utf8)), case .object(let e) = value,
              case .number(let rawID)? = e["id"] else { return nil }
        let id = Int(rawID)
        switch e["kind"]?.stringValue {
        case "call":
            guard let ns = e["ns"]?.stringValue, let method = e["method"]?.stringValue else { return nil }
            guard case .array(let args)? = e["args"] else { return nil }
            self = .call(HostCall(id: id, namespace: ns, method: method, arguments: args))
        case "result":
            if case .bool(true)? = e["ok"] {
                self = .result(id: id, .success(e["value"] ?? .null))
            } else {
                let error = e["error"]
                self = .result(id: id, .failure(HostError(error?["code"]?.stringValue ?? "internal", error?["message"]?.stringValue ?? "Unknown error",
                                                          data: error?["data"], stack: error?["stack"]?.stringValue)))
            }
        default:
            return nil
        }
    }
}

/// What Baron sends a plugin's context.
enum InboundEnvelope {
    case result(id: Int, Result<JSONValue, HostError>)
    case dispatch(id: Int, target: DispatchTarget, name: String, payload: JSONValue)
    case cancel(id: Int)
    /// For an open view: `message` from its page, or `closed`.
    case event(view: String, name: String, payload: JSONValue)

    var json: String {
        var object: [String: JSONValue] = ["v": .number(1)]
        switch self {
        case .result(let id, .success(let value)):
            object.merge(["kind": .string("result"), "id": .number(Double(id)), "ok": .bool(true), "value": value]) { $1 }
        case .result(let id, .failure(let error)):
            var detail: [String: JSONValue] = ["code": .string(error.code), "message": .string(error.message)]
            if let data = error.data { detail["data"] = data }
            object.merge(["kind": .string("result"), "id": .number(Double(id)), "ok": .bool(false), "error": .object(detail)]) { $1 }
        case .dispatch(let id, let target, let name, let payload):
            object.merge(["kind": .string("dispatch"), "id": .number(Double(id)), "target": .string(target.rawValue), "name": .string(name), "payload": payload]) { $1 }
        case .cancel(let id):
            object.merge(["kind": .string("cancel"), "id": .number(Double(id))]) { $1 }
        case .event(let view, let name, let payload):
            object.merge(["kind": .string("event"), "view": .string(view), "name": .string(name), "payload": payload]) { $1 }
        }
        return JSONValue.object(object).jsonString
    }
}

/// The envelopes a plugin page's bridge exchanges with Baron: the same calls and results as an engine context's,
/// and the events its view receives.
public enum PageEnvelope {
    /// A call from the page; nil for anything else.
    public static func call(fromJSON json: String) -> HostCall? {
        if case .call(let call)? = OutboundEnvelope(json: json) { return call }
        return nil
    }

    public static func result(id: Int, _ result: Result<JSONValue, HostError>) -> String {
        InboundEnvelope.result(id: id, result).json
    }

    public static func event(view: String, name: String, payload: JSONValue) -> String {
        InboundEnvelope.event(view: view, name: name, payload: payload).json
    }
}

public enum DispatchTarget: String, Sendable {
    case action, options, button, lifecycle, event
}

extension Result {
    /// The error, when this is a failure.
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
