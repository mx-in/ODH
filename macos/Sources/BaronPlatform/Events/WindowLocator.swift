import BaronCore
import CoreGraphics
import Foundation

/// Finds the normal (layer 0) on-screen window under a point.
///
/// Window numbers and bounds need no extra permission; only titles would need Screen Recording.
public enum WindowLocator {
    public static func window(at point: CGPoint) -> WindowSnapshot? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        // The list is ordered front to back, so the first hit is the visible window.
        for info in list {
            guard
                (info[kCGWindowLayer as String] as? Int) == 0,
                let id = info[kCGWindowNumber as String] as? Int,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: boundsInfo),
                frame.contains(point)
            else { continue }
            return WindowSnapshot(id: id, frame: frame)
        }
        return nil
    }
}

