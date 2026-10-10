import BaronCore

/// `host.clipboard`. Reading needs `clipboard.read`; both need a user action (checked by the gate).
public struct ClipboardService: HostService {
    public let namespace = "clipboard"
    private let system: SystemActions

    public init(system: SystemActions) {
        self.system = system
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        switch method {
        case "readText": return .string(await system.readClipboard())
        case "writeText":
            await system.writeClipboard(try arguments.string(0))
            return .null
        default: throw arguments.unknownMethod()
        }
    }
}
