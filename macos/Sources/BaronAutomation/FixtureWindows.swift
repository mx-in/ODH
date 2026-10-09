import AppKit
import ApplicationServices
import BaronPlatform

/// Finds and closes the windows a UI test opened, and answers "save changes?" sheets with "don't save".
public enum FixtureWindows {
    static let discardTitles: Set<String> = ["Don’t Save", "Don't Save", "Delete", "Discard", "Delete Draft", "不存储", "删除"]

    public static func window(titled fragment: String, inApp pid: pid_t) -> AXElement? {
        let app = AXElement.application(pid: pid)
        let windows = (app.value(kAXWindowsAttribute) as? [AXUIElement])?.map(AXElement.init) ?? []
        return windows.first { ($0.title ?? "").localizedCaseInsensitiveContains(fragment) }
    }

    public static func waitForWindow(titled fragment: String, inApp pid: pid_t, timeout: TimeInterval = 10) -> AXElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let window = window(titled: fragment, inApp: pid) { return window }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    /// Raises the window so clicks land on it.
    public static func raise(_ window: AXElement) {
        AXUIElementPerformAction(window.raw, kAXRaiseAction as CFString)
        window.set(kAXMainAttribute, to: kCFBooleanTrue)
    }

    /// Presses the window's close button, then discards changes if a sheet asks.
    @discardableResult
    public static func close(_ window: AXElement) -> Bool {
        guard let button = window.element(kAXCloseButtonAttribute) else { return false }
        AXUIElementPerformAction(button.raw, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.6)
        discardSheet(on: window)
        return true
    }

    public static func discardSheet(on window: AXElement) {
        let children = (window.value(kAXChildrenAttribute) as? [AXUIElement])?.map(AXElement.init) ?? []
        for sheet in children where sheet.role == "AXSheet" {
            let buttons = (sheet.value(kAXChildrenAttribute) as? [AXUIElement])?.map(AXElement.init) ?? []
            if let discard = buttons.first(where: { $0.role == "AXButton" && discardTitles.contains($0.title ?? "") }) {
                AXUIElementPerformAction(discard.raw, kAXPressAction as CFString)
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
    }
}

/// Detects Baron's action bar from the window list (owner name only; needs no Screen Recording).
public enum BaronBarDetector {
    public static func isVisible() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { info in
            (info[kCGWindowOwnerName as String] as? String) == "Baron" && ((info[kCGWindowLayer as String] as? Int) ?? 0) > 0
        }
    }

    /// Polls until the bar shows or `timeout` passes.
    public static func waitForBar(timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isVisible() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }
}

extension BaronBarDetector {
    /// Presses a bar button through Accessibility, e.g. `builtin.copy`. Returns false if it isn't there.
    @discardableResult
    public static func pressAction(_ id: String) -> Bool {
        guard let baron = NSRunningApplication.runningApplications(withBundleIdentifier: "org.odh.baron").first else { return false }
        let app = AXElement.application(pid: baron.processIdentifier)
        let windows = (app.value(kAXWindowsAttribute) as? [AXUIElement])?.map(AXElement.init) ?? []
        var queue = windows
        while !queue.isEmpty {
            let element = queue.removeFirst()
            if element.string("AXIdentifier") == "baron.action.\(id)" {
                return AXUIElementPerformAction(element.raw, kAXPressAction as CFString) == .success
            }
            queue += (element.value(kAXChildrenAttribute) as? [AXUIElement])?.map(AXElement.init) ?? []
        }
        return false
    }
}
