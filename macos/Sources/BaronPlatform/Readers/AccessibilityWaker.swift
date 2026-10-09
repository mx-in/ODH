import AppKit
import ApplicationServices

/// Asks apps that build their accessibility tree on demand to build it.
///
/// - Chrome builds a basic tree once a client reads the app's `AXRole`.
/// - Electron apps (VS Code, Slack, Obsidian) build one after `AXManualAccessibility` is set.
/// - iWork apps (Pages, Numbers, Keynote) expose their document text only after
///   `AXEnhancedUserInterface` is set, though the call reports an error. Setting it is known to
///   slow some window animations, so it is limited to the apps that need it.
public enum AccessibilityWaker {
    public static let manualAccessibilityAttribute = "AXManualAccessibility"
    public static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"
    public static let enhancedUserInterfaceApps: Set<String> = [
        "com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote",
    ]

    public struct Result {
        /// The app accepted `AXManualAccessibility`, so it is Electron-based.
        public let manualAccessibilitySet: Bool
        public let role: String?
    }

    @discardableResult
    public static func wake(_ app: AXElement) -> Result {
        let manual = app.set(manualAccessibilityAttribute, to: kCFBooleanTrue)
        if let pid = app.pid,
           let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           enhancedUserInterfaceApps.contains(id) {
            app.set(enhancedUserInterfaceAttribute, to: kCFBooleanTrue)
        }
        return Result(manualAccessibilitySet: manual, role: app.role)
    }
}
