import Foundation

/// What Baron does after a plugin action returns. Design: 03-host-api-and-ipc.md#action-results
public enum PluginActionResult: Equatable, Sendable {
    case nothing
    case copy(String)
    case replace(String)
    case toast(String, kind: String)
    case openURL(URL)

    /// Reads an action's return value. `editable` and `mayReplace` (the plugin holds `selection.replace`)
    /// decide whether a replace is allowed; the message explains a refusal.
    public static func parse(_ value: JSONValue, editable: Bool, mayReplace: Bool) -> Result<PluginActionResult, PluginActionResultError> {
        guard case .object(let result) = value else {
            return value == .null ? .success(.nothing) : .failure(.init("The action returned something other than a result object"))
        }
        let text = result["text"]?.stringValue
        switch result["type"]?.stringValue {
        case "copy":
            guard let text else { return .failure(.init("A copy result needs text")) }
            return .success(.copy(text))
        case "replace":
            guard let text else { return .failure(.init("A replace result needs text")) }
            guard mayReplace else { return .failure(.init("The plugin can't replace text: it doesn't have the selection.replace permission")) }
            guard editable else { return .failure(.init("This selection can't be replaced")) }
            return .success(.replace(text))
        case "toast":
            guard let message = result["message"]?.stringValue else { return .failure(.init("A toast result needs a message")) }
            let kind = result["kind"]?.stringValue ?? "info"
            guard ["info", "success", "error"].contains(kind) else { return .failure(.init("A toast's kind is info, success or error")) }
            return .success(.toast(message, kind: kind))
        case "openUrl":
            guard let text = result["url"]?.stringValue, let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else {
                return .failure(.init("An openUrl result needs an https, http or mailto URL"))
            }
            return .success(.openURL(url))
        default:
            return .failure(.init("Unknown result type \(result["type"]?.stringValue ?? "(missing)")"))
        }
    }
}

public struct PluginActionResultError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}
