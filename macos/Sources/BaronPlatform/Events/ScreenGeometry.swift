import AppKit

/// Converts between AppKit's bottom-left screen origin and the top-left origin
/// that Accessibility, Core Graphics windows and `BaronCore` use.
public enum ScreenGeometry {
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    public static func topLeft(fromAppKit point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func appKit(fromTopLeft rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func topLeft(fromAppKit rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The visible frame (minus menu bar and Dock) of the screen holding `point`, top-left origin.
    public static func visibleFrame(containing point: CGPoint) -> CGRect {
        let appKitPoint = NSPoint(x: point.x, y: primaryHeight - point.y)
        let screen = NSScreen.screens.first { NSMouseInRect(appKitPoint, $0.frame, false) } ?? NSScreen.main
        return topLeft(fromAppKit: screen?.visibleFrame ?? .zero)
    }
}
