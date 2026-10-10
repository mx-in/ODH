import BaronCore
import Darwin
import Foundation

/// What `baron dev` asks of Baron: load a folder as a development plugin, and reload it after a rebuild.
public protocol DevSessionHandler: Sendable {
    /// Loads the folder as a development plugin; returns its id, or throws why it can't.
    func register(folder: URL) async throws -> String
    func reload(pluginID: String) async
    func unregister(pluginID: String) async
}

/// Developer mode's socket: a Unix socket only this user can open (0600, in Baron's Application Support folder).
/// `baron dev` sends JSON lines (`register`, `reload`); Baron answers and streams the plugin's log lines and errors
/// back. Design: 09-developer-tooling.md#development-mode
public final class DevServer: @unchecked Sendable {
    public let path: URL
    private let handler: DevSessionHandler
    private let queue = DispatchQueue(label: "org.odh.baron.dev")
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private let lock = NSLock()

    final class Client: @unchecked Sendable {
        let socket: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        var plugins = Set<String>()
        init(socket: Int32) { self.socket = socket }
    }

    public static var standardPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Baron.name).appendingPathComponent("dev.sock")
    }

    public init(path: URL = DevServer.standardPath, handler: DevSessionHandler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HostError.internalError("socket() failed") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); throw HostError.internalError("Socket path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, chmod(path.path, 0o600) == 0, listen(fd, 4) == 0 else { close(fd); throw HostError.internalError("Can't listen on \(path.path)") }
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        acceptSource = source
    }

    public func stop() {
        acceptSource?.cancel()
        if listener >= 0 { close(listener) }
        listener = -1
        lock.withLock { clients.values.forEach { $0.source?.cancel(); close($0.socket) }; clients.removeAll() }
        unlink(path.path)
    }

    private func accept() {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return }
        let client = Client(socket: fd)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.read(client) }
        source.resume()
        client.source = source
        lock.withLock { clients[fd] = client }
    }

    private func read(_ client: Client) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.read(client.socket, &chunk, chunk.count)
        guard count > 0 else { return disconnect(client) }
        client.buffer.append(contentsOf: chunk[0..<count])
        while let newline = client.buffer.firstIndex(of: 10) {
            let line = client.buffer[client.buffer.startIndex..<newline]
            client.buffer.removeSubrange(client.buffer.startIndex...newline)
            if let message = try? JSONValue(data: Data(line)) { handle(message, from: client) }
        }
    }

    private func handle(_ message: JSONValue, from client: Client) {
        let handler = self.handler
        Task {
            switch message["op"]?.stringValue {
            case "register":
                do {
                    let id = try await handler.register(folder: URL(fileURLWithPath: message["folder"]?.stringValue ?? ""))
                    lock.withLock { _ = client.plugins.insert(id) }
                    send(.object(["ok": .bool(true), "id": .string(id)]), to: client)
                } catch {
                    send(.object(["ok": .bool(false), "error": .string((error as? InstallError)?.description ?? "\(error)")]), to: client)
                }
            case "reload":
                let id = message["id"]?.stringValue ?? ""
                await handler.reload(pluginID: id)
                send(.object(["ok": .bool(true)]), to: client)
            default:
                send(.object(["ok": .bool(false), "error": .string("Unknown op")]), to: client)
            }
        }
    }

    private func disconnect(_ client: Client) {
        client.source?.cancel()
        close(client.socket)
        let plugins = lock.withLock { clients.removeValue(forKey: client.socket)?.plugins ?? [] }
        let handler = self.handler
        Task { for id in plugins { await handler.unregister(pluginID: id) } }
    }

    private func send(_ message: JSONValue, to client: Client) {
        let line = Array((message.jsonString + "\n").utf8)
        queue.async { _ = line.withUnsafeBytes { Darwin.write(client.socket, $0.baseAddress, line.count) } }
    }

    /// Streams a log line or error to the sessions that registered the plugin.
    public func emit(pluginID: String, event: String, fields: [String: JSONValue]) {
        let targets = lock.withLock { clients.values.filter { $0.plugins.contains(pluginID) } }
        let message = JSONValue.object(fields.merging(["event": .string(event), "id": .string(pluginID)]) { a, _ in a })
        for client in targets { send(message, to: client) }
    }
}
