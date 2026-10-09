import ApplicationServices

/// Asks Chromium-based apps to build their accessibility tree.
///
/// Chrome builds a basic tree once a client reads the app's `AXRole`. Electron apps
/// (VS Code, Slack, Obsidian) only build one after `AXManualAccessibility` is set.
public enum AccessibilityWaker {
    public static let manualAccessibilityAttribute = "AXManualAccessibility"

    public struct Result {
        /// The app accepted `AXManualAccessibility`, so it is Electron-based.
        public let manualAccessibilitySet: Bool
        public let role: String?
    }

    @discardableResult
    public static func wake(_ app: AXElement) -> Result {
        let manual = app.set(manualAccessibilityAttribute, to: kCFBooleanTrue)
        return Result(manualAccessibilitySet: manual, role: app.role)
    }
}
