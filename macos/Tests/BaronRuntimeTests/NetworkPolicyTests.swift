import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

@Suite(.serialized)
struct NetworkPolicyTests {
    let grants = GrantStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("baron-net-\(UUID().uuidString)"))

    func service() -> HTTPService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return HTTPService(configuration: configuration, policy: NetworkPolicy(grants: grants, resolve: { _ in ["93.184.216.34"] }))
    }

    func fetch(_ url: String, _ plugin: RuntimePlugin) async -> Result<JSONValue, HostError> {
        await HostRouter(services: [service()]).handle(HostCall(id: 1, namespace: "http", method: "fetch", arguments: [.string(url), .object([:])]), from: plugin)
    }

    func stub(_ url: String, _ reply: StubProtocol.Reply) {
        StubProtocol.lock.withLock { StubProtocol.replies[url] = reply }
    }

    @Test func fetchesDeclaredHostsOnly() async throws {
        let plugin = try pluginWith(permissions: ["network:policy.example"])
        stub("https://policy.example/ok", .init(body: Data("ok".utf8)))
        #expect(try await fetch("https://policy.example/ok", plugin).get()["body"] == .string("ok"))
        let refused = await fetch("https://other.example/", plugin).failure
        #expect(refused?.code == "permission_denied")
        #expect(refused?.data == .object(["permission": .string("network:other.example"), "requestable": .bool(false)]))
        #expect(await fetch("http://policy.example/ok", plugin).failure?.data?["permission"] == .string("network:http://policy.example"))
    }

    @Test func saysAnUndeclaredHostCanBeAskedFor() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["network:*"])
        #expect(await fetch("https://ask.example/", plugin).failure?.data?["requestable"] == .bool(true))
        await grants.record(.deny, for: "network:ask.example", pluginID: plugin.id)
        #expect(await fetch("https://ask.example/", plugin).failure?.data?["requestable"] == .bool(false))
        await grants.record(.alwaysAllow, for: "network:granted.example", pluginID: plugin.id)
        stub("https://granted.example/", .init(body: Data("yes".utf8)))
        #expect(try await fetch("https://granted.example/", plugin).get()["body"] == .string("yes"))
    }

    @Test func checksEveryRedirectHop() async throws {
        let plugin = try pluginWith(permissions: ["network:hop.example"])
        stub("https://hop.example/a", .init(redirect: "https://hop.example/b"))
        stub("https://hop.example/b", .init(body: Data("b".utf8)))
        #expect(try await fetch("https://hop.example/a", plugin).get()["body"] == .string("b"))
        stub("https://hop.example/leave", .init(redirect: "https://elsewhere.example/steal"))
        stub("https://elsewhere.example/steal", .init(body: Data("stolen".utf8)))
        let refused = await fetch("https://hop.example/leave", plugin).failure
        #expect(refused?.code == "permission_denied")
        #expect(refused?.data?["permission"] == .string("network:elsewhere.example"))
    }

    @Test func refusesPublicNamesThatLeadToPrivateAddresses() async throws {
        let plugin = try pluginWith(permissions: ["network:rebind.example", "network:fine.example", "network:localhost:8765", "network:192.168.1.10"])
        let policy = NetworkPolicy(grants: grants) { host in
            ["rebind.example": ["192.168.1.1"], "fine.example": ["93.184.216.34"], "localhost": ["127.0.0.1"]][host] ?? []
        }
        let refused = await policy.check(URL(string: "https://rebind.example/")!, for: plugin)
        #expect(refused?.code == "permission_denied" && refused?.data?["reason"] == .string("private_address"))
        #expect(await policy.check(URL(string: "https://fine.example/")!, for: plugin) == nil)
        #expect(await policy.check(URL(string: "http://localhost:8765/")!, for: plugin) == nil)
        #expect(await policy.check(URL(string: "https://192.168.1.10/")!, for: plugin) == nil)
    }

    @Test func theSystemResolverAnswers() async {
        let addresses = await NetworkPolicy.systemResolve("localhost")
        #expect(addresses.contains("127.0.0.1") || addresses.contains("[::1]"))
    }
}
