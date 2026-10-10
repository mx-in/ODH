import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

final class ScriptedPrompter: PermissionPrompter, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    private var active = 0
    private(set) var overlapped = false
    var answer: PromptAnswer
    init(_ answer: PromptAnswer) { self.answer = answer }
    var questions: [String] { lock.withLock { asked } }

    func ask(_ request: PermissionRequest) async -> PromptAnswer {
        lock.withLock { asked.append("\(request.pluginName): \(request.permission)"); active += 1; if active > 1 { overlapped = true } }
        try? await Task.sleep(for: .milliseconds(20))
        lock.withLock { active -= 1 }
        return answer
    }
}

struct PermissionServiceTests {
    let grants = GrantStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("baron-perm-\(UUID().uuidString)"))

    func call(_ service: PermissionService, _ method: String, _ names: [String], plugin: RuntimePlugin) async -> Result<JSONValue, HostError> {
        await HostRouter(services: [service]).handle(HostCall(id: 1, namespace: "permissions", method: method, arguments: [.array(names.map(JSONValue.string))]), from: plugin)
    }

    @Test func queryReportsGrantedPromptAndDenied() async throws {
        let plugin = try pluginWith(permissions: ["network:dict.cn", "secrets"], optional: ["network:*", "clipboard.read"])
        let service = PermissionService(grants: grants, prompter: ScriptedPrompter(.deny))
        let states = try await call(service, "query", ["network:dict.cn", "secrets", "clipboard.read", "network:other.example", "selection.replace", "nonsense"], plugin: plugin).get()
        #expect(states == .object(["network:dict.cn": .string("granted"), "secrets": .string("granted"), "clipboard.read": .string("prompt"),
                                   "network:other.example": .string("prompt"), "selection.replace": .string("denied"), "nonsense": .string("denied")]))
    }

    @Test func requestPromptsAndRemembersTheAnswer() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["network:*"])
        let prompter = ScriptedPrompter(.alwaysAllow)
        let service = PermissionService(grants: grants, prompter: prompter)
        #expect(try await call(service, "request", ["network:dict.cn"], plugin: plugin).get() == .array([.string("network:dict.cn")]))
        #expect(try await call(service, "request", ["network:dict.cn"], plugin: plugin).get() == .array([.string("network:dict.cn")]))
        #expect(prompter.questions == ["Test: network:dict.cn"])
    }

    @Test func aDenialIsntAskedAgain() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["network:*"])
        let prompter = ScriptedPrompter(.deny)
        let service = PermissionService(grants: grants, prompter: prompter)
        #expect(try await call(service, "request", ["network:dict.cn"], plugin: plugin).get() == .array([]))
        #expect(try await call(service, "request", ["network:dict.cn"], plugin: plugin).get() == .array([]))
        #expect(prompter.questions.count == 1)
    }

    @Test func refusesPermissionsTheManifestDoesntOffer() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["network:*"])
        let service = PermissionService(grants: grants, prompter: ScriptedPrompter(.alwaysAllow))
        #expect(await call(service, "request", ["clipboard.read"], plugin: plugin).failure?.code == "invalid_argument")
        #expect(await call(service, "request", ["network:*"], plugin: plugin).failure?.code == "invalid_argument")
    }

    @Test func promptsOneAtATime() async throws {
        let a = try pluginWith(permissions: [], optional: ["network:*"])
        let b = try pluginWith(permissions: [], optional: ["network:*"])
        let prompter = ScriptedPrompter(.allowOnce)
        let service = PermissionService(grants: grants, prompter: prompter)
        async let first = call(service, "request", ["network:a.example", "network:b.example"], plugin: a)
        async let second = call(service, "request", ["network:c.example"], plugin: b)
        _ = await (first, second)
        #expect(prompter.questions.count == 3)
        #expect(!prompter.overlapped)
    }
}
