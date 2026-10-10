import BaronCore

/// `host.selection.replace`: needs `selection.replace` and a user action (the gate), and an editable selection.
public struct SelectionService: HostService {
    public let namespace = "selection"
    private let system: SystemActions

    public init(system: SystemActions) {
        self.system = system
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        guard method == "replace" else { throw arguments.unknownMethod() }
        guard await system.replaceSelection(with: try arguments.string(0)) else {
            throw HostError.invalidArgument("The selection can't be replaced: it isn't in an editable field")
        }
        return .null
    }
}
