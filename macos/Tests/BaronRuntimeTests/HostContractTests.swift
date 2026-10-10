import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

/// packages/test/contract/host-contract.json against Baron's real router, gate, grants, network policy and services;
/// @baron/test runs the same corpus against its mock host on both engines. Skipped when Bun isn't installed.
@Suite(.serialized)
struct HostContractTests {
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        struct Mock: Decodable, Sendable { var url: String; var status: Int; var body: String }
        var name: String
        var permissions: [String]?
        var optional: [String]?
        var userAction: Bool?
        var mock: Mock?
        var call: [JSONValue]
        var expect: JSONValue
        var testDescription: String { name }
    }

    struct Contract: Decodable, Sendable {
        var clipboard: String
        var promptAnswer: PromptAnswer
        var cases: [Case]
    }

    static let folder = ExamplePluginTests.repository.appendingPathComponent("packages/test/contract")
    static let contract: Contract? = try? JSONDecoder().decode(Contract.self, from: Data(contentsOf: folder.appendingPathComponent("host-contract.json")))

    static let plugin: RuntimePlugin? = {
        guard let bun = ExamplePluginTests.bun else { return nil }
        let package = folder.appendingPathComponent("plugin")
        let build = Process()
        build.executableURL = URL(fileURLWithPath: bun)
        build.arguments = [ExamplePluginTests.repository.appendingPathComponent("packages/cli/bin/baron.ts").path, "build", package.path]
        build.standardOutput = FileHandle.nullDevice
        guard (try? build.run()) != nil else { return nil }
        build.waitUntilExit()
        return ManifestValidator().validate(package: package).manifest.map { RuntimePlugin(manifest: $0, package: package) }
    }()

    @Test func theContractIsThere() {
        #expect((Self.contract?.cases.count ?? 0) >= 20)
    }

    @Test(.enabled(if: ExamplePluginTests.bun != nil, "needs Bun"), arguments: contract?.cases ?? [])
    func baronHonoursTheContract(_ c: Case) async throws {
        let contract = try #require(Self.contract)
        let base = try #require(Self.plugin)
        var manifest = base.manifest
        manifest.permissions = c.permissions ?? []
        manifest.optionalPermissions = c.optional ?? []
        let plugin = RuntimePlugin(manifest: manifest, package: base.package)

        let grants = GrantStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("baron-contract-\(UUID().uuidString)"))
        let actions = UserActionTracker()
        if c.userAction != false { actions.record(plugin.id) }
        let system = FakeSystem()
        system.clipboard = contract.clipboard
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        if let mock = c.mock {
            StubProtocol.lock.withLock { StubProtocol.replies[mock.url] = .init(status: mock.status, body: Data(mock.body.utf8)) }
        }
        let services: [HostService] = [
            LogService(), UIService(presenter: RecordingPresenter(), system: system),
            HTTPService(configuration: configuration, policy: NetworkPolicy(grants: grants, resolve: { _ in ["93.184.216.34"] })),
            ClipboardService(system: system), SelectionService(system: system), TextService(),
            PermissionService(grants: grants, prompter: ScriptedPrompter(contract.promptAnswer)),
        ]
        let runtime = PluginRuntime(handler: HostRouter(services: services, gate: PermissionGate(grants: grants, actions: actions)))
        await runtime.register(plugin)

        guard case .string(let ns) = c.call[0], case .string(let method) = c.call[1] else { Issue.record("bad case"); return }
        let request = JSONValue.object(["ns": .string(ns), "method": .string(method), "args": c.call[2]]).jsonString
        let context = JSONValue.object(["text": .string(request), "source": .string("ax-text"), "editable": .bool(true),
                                        "app": .object(["id": .string("a"), "name": .string("A"), "pid": .number(1)]), "platform": .string("macos")])
        let result = try await runtime.dispatch(plugin.id, .action, name: "call", payload: DispatchPayload(context: context)).get()
        guard case .string(let text)? = result["text"] else { Issue.record("no answer: \(result)"); return }
        let answer = try JSONValue(data: Data(text.utf8))

        if let code = c.expect["code"] {
            #expect(answer == .object(["ok": .bool(false), "code": code]))
        } else {
            #expect(answer["ok"] == .bool(true), "\(answer)")
            #expect(Self.contains(answer["value"] ?? .null, c.expect["value"] ?? .null), "\(answer)")
        }
    }

    /// Whether `actual` has every field of `expected`, so Baron may add fields such as headers.
    static func contains(_ actual: JSONValue, _ expected: JSONValue) -> Bool {
        switch (actual, expected) {
        case (.object(let a), .object(let e)): return e.allSatisfy { key, value in a[key].map { contains($0, value) } ?? false }
        case (.array(let a), .array(let e)): return a.count == e.count && zip(a, e).allSatisfy(contains)
        default: return actual == expected
        }
    }
}
