import AppKit
import ApplicationServices

/// Whether this process may read other apps through the Accessibility API.
public enum AccessibilityPermission {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt the first time; later calls only report the state.
    @discardableResult
    public static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
