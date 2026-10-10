import Foundation

/// The context being read for the current selection. Reading starts off the main thread as soon as the text is
/// known; an action that needs it waits at most `actionWait` more, then runs with whatever arrived.
/// Design: docs/tec-design.md#context-capture
@MainActor
public final class ContextCapture {
    public static let actionWait: Duration = .milliseconds(300)

    public let fields: Set<ContextField>
    private var result: CapturedContext?
    private var waiters: [UUID: CheckedContinuation<CapturedContext?, Never>] = [:]

    /// `read` runs on a background thread, and only when `fields` isn't empty.
    public init(_ fields: Set<ContextField>, read: @escaping @Sendable (Set<ContextField>) -> CapturedContext) {
        self.fields = fields
        guard !fields.isEmpty else {
            result = CapturedContext()
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let context = read(fields)
            await self?.finish(context)
        }
    }

    /// The context, waiting at most `limit` for it; nil when it isn't ready by then.
    public func value(waitingAtMost limit: Duration = actionWait) async -> CapturedContext? {
        if let result { return result }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: limit)
                self?.waiters.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
    }

    private func finish(_ context: CapturedContext) {
        result = context
        for waiter in waiters.values { waiter.resume(returning: context) }
        waiters.removeAll()
    }
}
