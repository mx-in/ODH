import ApplicationServices
import BaronPlatform
import CoreGraphics
import Foundation

/// Finds where a word is drawn on screen by searching an app's Accessibility tree.
public enum WordLocator {
    public struct Hit {
        /// Where the word is drawn, in top-left-origin screen points.
        public let rect: CGRect
        /// How it was found: "exact element", "bounds for range" or "estimated".
        public let method: String

        public var point: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
        /// Just inside the word's left and right edges, where a drag starts or ends.
        public var leadingPoint: CGPoint { CGPoint(x: rect.minX + 1, y: rect.midY) }
        public var trailingPoint: CGPoint { CGPoint(x: rect.maxX - 1, y: rect.midY) }
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
            return Hit(rect: frame, method: "exact element")
        }
        let location = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound.samePosition(in: text.utf16)!)
        let request = AXElement.value(of: CFRange(location: location, length: word.utf16.count))
        if let rect = AXElement.rect(from: element.value(kAXBoundsForRangeParameterizedAttribute, parameter: request)), rect.width > 0 {
            return Hit(rect: rect, method: "bounds for range")
        }
        // A single line of text: assume even character widths (exact for monospaced editors).
        guard frame.height < 48 else { return nil }
        let unit = frame.width / CGFloat(max(text.utf16.count, 1))
        let rect = CGRect(x: frame.minX + unit * CGFloat(location), y: frame.minY, width: unit * CGFloat(word.utf16.count), height: frame.height)
        return Hit(rect: rect, method: "estimated")
    }

    static func frame(of element: AXElement) -> CGRect? {
        element.frame
    }
}
