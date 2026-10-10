import BaronCore
import Foundation

/// Asks a browser for its front page through `osascript`, which can run off the main thread and be stopped at
/// a time limit. macOS asks the user once per browser before the first answer (Automation).
public enum BrowserPageReader {
    public static let timeout: TimeInterval = 0.5

    public static func page(of bundleIdentifier: String, timeout: TimeInterval = timeout) -> CapturedContext.Page? {
        guard let source = BrowserPageScript.source(for: bundleIdentifier) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return BrowserPageScript.page(fromOutput: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
