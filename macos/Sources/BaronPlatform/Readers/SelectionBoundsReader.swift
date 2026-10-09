import ApplicationServices
import CoreGraphics

/// Reads where the selection sits on screen, in top-left-origin screen points.
public enum SelectionBoundsReader {
    public static func bounds(ofNativeSelectionIn element: AXElement) -> CGRect? {
        guard let range = NativeTextWindowReader.selectedRange(of: element) else { return nil }
        let rect = AXElement.rect(from: element.value(kAXBoundsForRangeParameterizedAttribute, parameter: AXElement.value(of: range)))
        return usable(rect)
    }

    public static func bounds(of range: AXTextMarkerRange, in element: AXElement) -> CGRect? {
        usable(AXElement.rect(from: element.value(kAXBoundsForTextMarkerRangeParameterizedAttribute, parameter: range)))
    }

    // Some apps answer with an empty rect at the origin instead of failing.
    private static func usable(_ rect: CGRect?) -> CGRect? {
        guard let rect, rect.width > 0 || rect.height > 0 else { return nil }
        return rect
    }
}
