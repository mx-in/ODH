import BaronCore
import Darwin
import Foundation
import Testing
@testable import BaronRuntime

final class RecordingDevHandler: DevSessionHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var calls: [String] { lock.withLock { log } }
    func register(folder: URL) async throws -> String {
        lock.withLock { log.append("register \(folder.lastPathComponent)") }
        if folder.lastPathComponent == "broken" { throw InstallError("Its manifest has problems.") }
        return "org.example.dev"
    }
    func reload(pluginID: String) async { lock.withLock { log.append("reload \(pluginID)") } }
    func unregister(pluginID: String) async { lock.withLock { log.append("unregister \(pluginID)") } }
}

/// A blocking client for the dev socket.
final class DevClient {
    let fd: Int32
    private var buffer = Data()

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes); $0[bytes.count] = 0 }
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { throw HostError.internalError("connect failed") }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    func send(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, bytes.count) }
    }

    func receive() -> JSONValue? {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                return try? JSONValue(data: Data(line))
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }

    deinit { close(fd) }
}

@Suite(.serialized)
struct DevServerTests {
    let path = URL(fileURLWithPath: "/tmp/baron-dev-\(UUID().uuidString.prefix(8)).sock")

    @Test func onlyThisUserCanOpenTheSocket() throws {
        let server = DevServer(path: path, handler: RecordingDevHandler())
        try server.start()
        defer { server.stop() }
        let mode = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func registersReloadsStreamsAndUnregisters() async throws {
        let handler = RecordingDevHandler()
        let server = DevServer(path: path, handler: handler)
        try server.start()
        defer { server.stop() }
        var client: DevClient? = try DevClient(path: path.path)
        client!.send(#"{"op": "register", "folder": "/tmp/my-plugin"}"#)
        #expect(client!.receive() == .object(["ok": .bool(true), "id": .string("org.example.dev")]))
        client!.send(#"{"op": "reload", "id": "org.example.dev"}"#)
        #expect(client!.receive() == .object(["ok": .bool(true)]))
        server.emit(pluginID: "org.example.dev", event: "log", fields: ["level": .string("info"), "text": .string("hello")])
        #expect(client!.receive()?["text"] == .string("hello"))
        server.emit(pluginID: "org.other", event: "log", fields: ["text": .string("not for this client")])
        client!.send(#"{"op": "register", "folder": "/tmp/broken"}"#)
        #expect(client!.receive()?["error"] == .string("Its manifest has problems."))
        client = nil
        try await Task.sleep(for: .milliseconds(200))
        #expect(handler.calls == ["register my-plugin", "reload org.example.dev", "register broken", "unregister org.example.dev"])
    }
}
