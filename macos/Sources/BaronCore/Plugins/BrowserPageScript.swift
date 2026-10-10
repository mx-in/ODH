import Foundation

/// AppleScript that asks a browser for its front page. Used for `page` when Accessibility doesn't expose the
/// address and the user turned on Settings › General › Advanced › Ask browsers for the page address.
/// Design: docs/tec-design.md#context-capture
public enum BrowserPageScript {
    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    /// The Chrome family: each answers Chrome's scripting dictionary.
    static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    /// The script for the browser, or nil when it isn't one Baron knows how to ask.
    public static func source(for bundleIdentifier: String) -> String? {
        if safari.contains(bundleIdentifier) {
            return "tell application id \"\(bundleIdentifier)\" to tell front document to return (URL as text) & linefeed & (name as text)"
        }
        if chromium.contains(bundleIdentifier) {
            return "tell application id \"\(bundleIdentifier)\" to tell active tab of front window to return (URL as text) & linefeed & (title as text)"
        }
        return nil
    }

    /// The page in the script's output: the address on the first line, the title on the second.
    public static func page(fromOutput output: String) -> CapturedContext.Page? {
        let lines = output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let address = lines.first, let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else { return nil }
        let title = lines.count > 1 && !lines[1].isEmpty ? lines[1] : nil
        return CapturedContext.Page(url: address, title: title)
    }
}
