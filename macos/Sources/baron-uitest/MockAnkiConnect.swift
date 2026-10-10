import Foundation
import Network

/// A tiny AnkiConnect on 127.0.0.1:18765 for baron-uitest --settings: answers deckNames, modelNames,
/// modelFieldNames and version, and logs each action it was asked.
final class MockAnkiConnect: @unchecked Sendable {
    static let port: UInt16 = 18765
    private let listener: NWListener
    private let lock = NSLock()
    private var asked: [String] = []
    var requests: [String] { lock.withLock { asked } }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: .global())
    }

    func stop() { listener.cancel() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global())
        var buffer = Data()
        func read() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, _ in
                if let data { buffer.append(data) }
                if let reply = self?.reply(to: buffer) {
                    connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
                } else if !done {
                    read()
                } else {
                    connection.cancel()
                }
            }
        }
        read()
    }

    /// The HTTP response once a whole request has arrived.
    private func reply(to request: Data) -> Data? {
        guard let text = String(data: request, encoding: .utf8), let split = text.range(of: "\r\n\r\n") else { return nil }
        let head = text[..<split.lowerBound].lowercased()
        let length = head.split(separator: "\r\n").first { $0.hasPrefix("content-length:") }.flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
        let body = String(text[split.upperBound...])
        guard body.utf8.count >= length else { return nil }
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        let action = json["action"] as? String ?? "?"
        let params = json["params"] as? [String: Any] ?? [:]
        let result: Any
        switch action {
        case "deckNames": result = ["Default", "Vocabulary"]
        case "modelNames": result = ["Basic", "Cloze"]
        case "modelFieldNames": result = (params["modelName"] as? String) == "Cloze" ? ["Text", "Back Extra"] : ["Front", "Back"]
        case "version": result = 6
        default: result = NSNull()
        }
        lock.withLock { asked.append(action + ((params["modelName"] as? String).map { "(\($0))" } ?? "")) }
        let payload = try! JSONSerialization.data(withJSONObject: ["result": result, "error": NSNull()])
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(payload)
        return response
    }
}
