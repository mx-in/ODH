import BaronCore
import Foundation

/// One `host` namespace, such as `http` or `log`.
public protocol HostService: Sendable {
    var namespace: String { get }
    /// Throws `HostError` for failures the plugin should see.
    func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue
}

/// Routes each call to its namespace's service. Every call passes `check` first, which is where task-006's
/// permission gate and user-action tracker plug in; no service can skip it. Design: 03-host-api-and-ipc.md#transports
public struct HostRouter: HostCallHandler {
    public typealias Check = @Sendable (HostCall, RuntimePlugin) async -> HostError?

    private let services: [String: HostService]
    private let check: Check

    public init(services: [HostService], check: @escaping Check = { _, _ in nil }) {
        self.services = Dictionary(services.map { ($0.namespace, $0) }, uniquingKeysWith: { _, last in last })
        self.check = check
    }

    public func handle(_ call: HostCall, from plugin: RuntimePlugin) async -> Result<JSONValue, HostError> {
        guard let service = services[call.namespace] else {
            return .failure(.invalidArgument("host.\(call.namespace) doesn't exist"))
        }
        if let refusal = await check(call, plugin) { return .failure(refusal) }
        do {
            return .success(try await service.call(call.method, HostArguments(call), plugin: plugin))
        } catch let error as HostError {
            return .failure(error)
        } catch {
            return .failure(.internalError("host.\(call.namespace).\(call.method) failed: \(error)"))
        }
    }
}

/// A call's arguments, read with errors that point at the bad one (`data.path`).
public struct HostArguments: Sendable {
    public let call: HostCall
    public var values: [JSONValue] { call.arguments }

    init(_ call: HostCall) {
        self.call = call
    }

    public func unknownMethod() -> HostError {
        .invalidArgument("host.\(call.namespace).\(call.method) doesn't exist")
    }

    func invalid(_ index: Int, _ expected: String) -> HostError {
        HostError("invalid_argument", "Argument \(index + 1) of host.\(call.namespace).\(call.method) must be \(expected)", data: .object(["path": .string("/\(index)")]))
    }

    public func string(_ index: Int) throws -> String {
        guard index < values.count, case .string(let text) = values[index] else { throw invalid(index, "a string") }
        return text
    }

    public func optionalString(_ index: Int) throws -> String? {
        guard index < values.count, values[index] != .null else { return nil }
        return try string(index)
    }

    public func object(_ index: Int) throws -> [String: JSONValue] {
        guard index < values.count else { return [:] }
        if values[index] == .null { return [:] }
        guard case .object(let members) = values[index] else { throw invalid(index, "an object") }
        return members
    }

    public func number(_ index: Int) throws -> Double {
        guard index < values.count, case .number(let n) = values[index] else { throw invalid(index, "a number") }
        return n
    }
}
