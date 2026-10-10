import Foundation
@testable import BaronRuntime

/// Collects what a context sends and lets tests wait for a particular envelope.
final class Outbox: @unchecked Sendable {
    private let lock = NSLock()
    private var envelopes: [[String: Any]] = []

    func append(_ json: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
        lock.withLock { envelopes.append(object) }
    }

    var all: [[String: Any]] { lock.withLock { envelopes } }

    func wait(timeout: Duration = .seconds(2), for predicate: ([String: Any]) -> Bool) async throws -> [String: Any] {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while clock.now < end {
            if let found = all.first(where: predicate) { return found }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw HarnessError.timedOut(all.map { "\($0)" }.joined(separator: "\n"))
    }

    enum HarnessError: Error { case timedOut(String) }
}

enum Envelopes {
    nonisolated(unsafe) static let environment: [String: Any] = ["apiVersion": 1, "baronVersion": "0.1.0", "pluginVersion": "1.0.0", "platform": "macos", "locale": "en", "appearance": "light", "development": false]
    nonisolated(unsafe) static let context: [String: Any] = ["text": "fox", "source": "ax-text", "editable": true, "app": ["id": "a", "name": "A", "pid": 1], "platform": "macos"]

    static func json(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    static func dispatch(id: Int, action: String, context: [String: Any] = context) -> String {
        json(["v": 1, "kind": "dispatch", "id": id, "target": "action", "name": action, "payload": ["environment": environment, "preferences": [:], "context": context]])
    }

    static func result(id: Int, value: Any) -> String {
        json(["v": 1, "kind": "result", "id": id, "ok": true, "value": value])
    }
}
