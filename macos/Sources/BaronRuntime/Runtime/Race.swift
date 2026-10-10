import Foundation

/// Waits for `body` or for `limit`, whichever comes first, and returns without waiting for the other.
/// (A task group would wait for a body that never returns.)
func withRace(_ limit: Duration, timeout: Error, _ body: @escaping @Sendable () async throws -> Void) async throws {
    let gate = RaceGate()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        gate.set(continuation)
        let work = Task {
            do { try await body(); gate.finish(.success(())) } catch { gate.finish(.failure(error)) }
        }
        Task {
            try? await Task.sleep(for: limit)
            if gate.finish(.failure(timeout)) { work.cancel() }
        }
    }
}

/// Resumes a continuation exactly once.
final class RaceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    func set(_ continuation: CheckedContinuation<Void, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    @discardableResult
    func finish(_ result: Result<Void, Error>) -> Bool {
        guard let continuation = lock.withLock({ () -> CheckedContinuation<Void, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }) else { return false }
        continuation.resume(with: result)
        return true
    }
}
