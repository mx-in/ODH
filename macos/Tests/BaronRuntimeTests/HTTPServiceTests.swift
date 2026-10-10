import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

/// Answers requests from a table instead of the network.
final class StubProtocol: URLProtocol {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var redirect: String?
        var delay: Double = 0
    }
    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var seen: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!.absoluteString
        let reply = Self.lock.withLock { () -> Reply? in
            var copy = request
            if let stream = request.httpBodyStream {
                stream.open(); var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: 4096); if n <= 0 { break }; data.append(buffer, count: n) }
                copy.httpBody = data
            }
            Self.seen.append(copy)
            return Self.replies[url]
        }
        guard let reply else { return client!.urlProtocol(self, didFailWithError: URLError(.cannotFindHost)) }
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            if let target = reply.redirect {
                let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": target])!
                client!.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: target)!), redirectResponse: response)
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
            client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client!.urlProtocol(self, didLoad: reply.body)
            client!.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct HTTPServiceTests {
    let plugin: RuntimePlugin
    let service: HTTPService

    init() throws {
        plugin = try makePlugin("")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        var limits = HTTPService.Limits()
        limits.maximumBody = 1024
        service = HTTPService(limits: limits, configuration: configuration)
        StubProtocol.lock.withLock { StubProtocol.replies = [:]; StubProtocol.seen = [] }
    }

    func stub(_ url: String, _ reply: StubProtocol.Reply) {
        StubProtocol.lock.withLock { StubProtocol.replies[url] = reply }
    }

    func fetch(_ url: String, _ init_: [String: JSONValue] = [:]) async -> Result<JSONValue, HostError> {
        await HostRouter(services: [service]).handle(HostCall(id: 1, namespace: "http", method: "fetch", arguments: [.string(url), .object(init_)]), from: plugin)
    }

    @Test func returnsStatusHeadersAndText() async throws {
        stub("https://dict.example/fox", .init(status: 200, headers: ["Content-Type": "text/html"], body: Data("<p>狐</p>".utf8)))
        let response = try await fetch("https://dict.example/fox").get()
        #expect(response["status"] == .number(200))
        #expect(response["headers"]?["content-type"] == .string("text/html"))
        #expect(response["body"] == .string("<p>狐</p>"))
    }

    @Test func sendsMethodHeadersAndBytesAndReturnsBytes() async throws {
        stub("https://anki.example/", .init(status: 201, body: Data([0, 255])))
        let response = try await fetch("https://anki.example/", ["method": .string("post"), "headers": .object(["X-Key": .string("1")]),
                                                                 "body": .object(["$bytes": .string("AQI=")]), "responseType": .string("bytes")]).get()
        #expect(response["body"] == .object(["$bytes": .string("AP8=")]))
        let sent = try #require(StubProtocol.lock.withLock { StubProtocol.seen.last })
        #expect(sent.httpMethod == "POST" && sent.value(forHTTPHeaderField: "X-Key") == "1" && sent.httpBody == Data([1, 2]))
    }

    @Test func non2xxIsAResponse() async throws {
        stub("https://dict.example/none", .init(status: 404))
        #expect(try await fetch("https://dict.example/none").get()["status"] == .number(404))
    }

    @Test func refusesOtherSchemesAndMethods() async {
        #expect(await fetch("file:///etc/passwd").failure?.code == "invalid_argument")
        #expect(await fetch("https://dict.example/", ["method": .string("TRACE")]).failure?.code == "invalid_argument")
    }

    @Test func limitsBodySize() async {
        stub("https://dict.example/big", .init(body: Data(repeating: 1, count: 2048)))
        let error = await fetch("https://dict.example/big").failure
        #expect(error?.code == "network_error" && error?.data?["reason"] == .string("too_large"))
    }

    @Test func followsRedirectsUpToFive() async throws {
        for i in 0..<6 { stub("https://r.example/\(i)", .init(redirect: "https://r.example/\(i + 1)")) }
        stub("https://r.example/6", .init(body: Data("end".utf8)))
        stub("https://r.example/5", .init(body: Data("five".utf8)))
        let followed = try await fetch("https://r.example/0").get()
        #expect(followed["body"] == .string("five"))
        #expect(followed["url"] == .string("https://r.example/5"))
        for i in 0..<7 { stub("https://loop.example/\(i)", .init(redirect: "https://loop.example/\(i + 1)")) }
        #expect(await fetch("https://loop.example/0").failure?.code == "network_error")
    }

    @Test func timesOutAndCancels() async throws {
        stub("https://slow.example/", .init(body: Data("late".utf8), delay: 1))
        #expect(await fetch("https://slow.example/", ["timeout": .number(100)]).failure?.code == "timeout")
        async let pending = fetch("https://slow.example/", ["requestID": .number(7)])
        try await Task.sleep(for: .milliseconds(100))
        _ = await HostRouter(services: [service]).handle(HostCall(id: 2, namespace: "http", method: "cancel", arguments: [.number(7)]), from: plugin)
        #expect(await pending.failure?.data?["reason"] == .string("cancelled"))
    }

    @Test func readsAFiveMegabyteBodyQuickly() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let roomy = HTTPService(configuration: configuration)
        stub("https://dict.example/large", .init(body: Data(repeating: 65, count: 5 * 1024 * 1024)))
        let clock = ContinuousClock()
        let start = clock.now
        let result = await HostRouter(services: [roomy]).handle(HostCall(id: 1, namespace: "http", method: "fetch", arguments: [.string("https://dict.example/large"), .object([:])]), from: plugin)
        #expect(try result.get()["status"] == .number(200))
        #expect(clock.now - start < .milliseconds(500))
    }
}
