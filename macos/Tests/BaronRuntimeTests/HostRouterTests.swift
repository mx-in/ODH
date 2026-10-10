import BaronCore
import Testing
@testable import BaronRuntime

struct EchoService: HostService {
    let namespace = "echo"
    func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        switch method {
        case "say": return .string(try arguments.string(0))
        case "fail": throw HostError("quota_exceeded", "full", data: .object(["limit": .number(1)]))
        case "crash": throw CocoaishError()
        default: throw arguments.unknownMethod()
        }
    }
    struct CocoaishError: Error {}
}

struct HostRouterTests {
    let plugin: RuntimePlugin
    init() throws { plugin = try makePlugin("") }

    func call(_ ns: String, _ method: String, _ args: [JSONValue], router: HostRouter = HostRouter(services: [EchoService()])) async -> Result<JSONValue, HostError> {
        await router.handle(HostCall(id: 1, namespace: ns, method: method, arguments: args), from: plugin)
    }

    @Test func routesToTheNamespace() async throws {
        #expect(try await call("echo", "say", [.string("fox")]).get() == .string("fox"))
    }

    @Test func unknownNamespacesAndMethodsAreInvalidArguments() async {
        #expect(await call("nope", "x", []).failure?.message == "host.nope doesn't exist")
        #expect(await call("echo", "shout", []).failure?.code == "invalid_argument")
    }

    @Test func badArgumentsPointAtThemselves() async {
        let error = await call("echo", "say", [.number(3)]).failure
        #expect(error?.code == "invalid_argument")
        #expect(error?.data == .object(["path": .string("/0")]))
    }

    @Test func serviceErrorsPassThroughAndOthersAreInternal() async {
        #expect(await call("echo", "fail", []).failure == HostError("quota_exceeded", "full", data: .object(["limit": .number(1)])))
        #expect(await call("echo", "crash", []).failure?.code == "internal")
    }

    @Test func everyCallPassesTheCheckFirst() async {
        let router = HostRouter(services: [EchoService()]) { call, _ in call.method == "say" ? HostError("permission_denied", "not granted") : nil }
        #expect(await call("echo", "say", [.string("x")], router: router).failure?.code == "permission_denied")
    }
}
