import ApplicationServices
import BaronPlatform
import CoreGraphics
import Foundation

/// Finds where a word is drawn on screen by searching an app's Accessibility tree.
public enum WordLocator {
    public struct Hit {
        public let point: CGPoint
        /// How the point was found: "exact element", "bounds for range" or "estimated".
        public let method: String
    }

    static let maxNodes = 6_000

    /// Searches the focused window (or every window) of `pid`, retrying until `timeout`.
    public static func locate(_ word: String, inApp pid: pid_t, timeout: TimeInterval = 8) -> Hit? {
        let app = AXElement.application(pid: pid)
        AccessibilityWaker.wake(app)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = search(word, in: windows(of: app)) { return hit }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    private static func windows(of app: AXElement) -> [AXElement] {
        var result: [AXElement] = []
        if let focused = app.element(kAXFocusedWindowAttribute) { result.append(focused) }
        if let all = app.value(kAXWindowsAttribute) as? [AXUIElement] {
            result += all.map(AXElement.init)
        }
        return result
    }

    private static func search(_ word: String, in roots: [AXElement]) -> Hit? {
        var queue = roots
        var visited = 0
        var estimate: Hit?
        while !queue.isEmpty, visited < maxNodes {
            let element = queue.removeFirst()
            visited += 1
            if let hit = match(word, element) {
                if hit.method != "estimated" { return hit }
                estimate = estimate ?? hit
            }
            if let children = element.value(kAXChildrenAttribute) as? [AXUIElement] {
                queue += children.map(AXElement.init)
            }
        }
        return estimate
    }

    private static func match(_ word: String, _ element: AXElement) -> Hit? {
        let text = element.string(kAXValueAttribute) ?? element.string(kAXTitleAttribute) ?? element.string(kAXDescriptionAttribute)
        guard let text, let range = text.range(of: word) else { return nil }
        guard let frame = frame(of: element), frame.width > 0, frame.height > 0 else { return nil }

        if text.trimmingCharacters(in: .whitespacesAndNewlines) == word {
            return Hit(point: CGPoint(x: frame.midX, y: frame.midY), method: "exact element")
        }
        let location = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound.samePosition(in: text.utf16)!)
        let request = AXElement.value(of: CFRange(location: location, length: word.utf16.count))
        if let rect = AXElement.rect(from: element.value(kAXBoundsForRangeParameterizedAttribute, parameter: request)), rect.width > 0 {
            return Hit(point: CGPoint(x: rect.midX, y: rect.midY), method: "bounds for range")
        }
        // A single line of text: assume even character widths (exact for monospaced editors).
        guard frame.height < 48 else { return nil }
        let fraction = (Double(location) + Double(word.utf16.count) / 2) / Double(max(text.utf16.count, 1))
        return Hit(point: CGPoint(x: frame.minX + frame.width * fraction, y: frame.midY), method: "estimated")
    }

    static func frame(of element: AXElement) -> CGRect? {
        guard
            let position = element.value(kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
            let size = element.value(kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}
