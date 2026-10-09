import AppKit
import BaronCore
import BaronPlatform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let permissionItem = NSMenuItem()
    private let coordinator = SelectionCoordinator(pipeline: SelectionPipeline(gate: Gate(excludedApps: ExcludedAppRule.defaults)))

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: Baron.name)
        item.menu = buildMenu()
        statusItem = item

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
        AXElement.applyGlobalTimeout()
        coordinator.start()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(Baron.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        updatePermissionItem()
        return menu
    }

    // The grant can change in System Settings at any time, so re-check each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        updatePermissionItem()
    }

    private func updatePermissionItem() {
        if AccessibilityPermission.isGranted {
            permissionItem.title = "Accessibility access granted"
            permissionItem.action = nil
        } else {
            permissionItem.title = "Grant Accessibility Access…"
            permissionItem.action = #selector(openAccessibilitySettings)
        }
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSystemSettings()
    }
}
