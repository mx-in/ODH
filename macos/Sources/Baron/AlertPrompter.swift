import AppKit
import BaronCore
import BaronRuntime

/// The run-time permission prompt: a native alert naming the plugin and what it asks for. Plugins never draw it.
/// The PermissionService shows one at a time. Design: 04-permissions-and-security.md#asking-at-run-time
final class AlertPrompter: PermissionPrompter {
    func ask(_ request: PermissionRequest) async -> PromptAnswer {
        await MainActor.run { Self.show(request) }
    }

    @MainActor
    static func show(_ request: PermissionRequest) -> PromptAnswer {
        let alert = NSAlert()
        let permission = PluginPermission(request.permission)
        alert.messageText = permission.map { PermissionWording.promptTitle(pluginName: request.pluginName, permission: $0) }
            ?? "“\(request.pluginName)” asks for \(request.permission)."
        alert.informativeText = "Allow Once lasts 10 minutes. You can change Always Allow in the plugin's settings. Deny is remembered for a day."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Always Allow").setAccessibilityIdentifier("baron.prompt.alwaysAllow")
        alert.addButton(withTitle: "Allow Once").setAccessibilityIdentifier("baron.prompt.allowOnce")
        let deny = alert.addButton(withTitle: "Deny")
        deny.setAccessibilityIdentifier("baron.prompt.deny")
        deny.keyEquivalent = "\u{1b}"
        alert.window.setAccessibilityIdentifier("baron.permissionPrompt")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .alwaysAllow
        case .alertSecondButtonReturn: return .allowOnce
        default: return .deny
        }
    }
}
