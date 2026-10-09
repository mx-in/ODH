import CoreGraphics

/// Where the action bar goes. All rects are top-left-origin screen points.
public enum BarPlacement {
    public static let gap: CGFloat = 8
    /// Distance above the pointer when the selection's bounds are unknown.
    public static let pointerOffset: CGFloat = 12

    /// Above the selection, centred on the pointer's x within it; below the selection when
    /// there is no room above; next to the pointer when bounds are unknown. Always kept on screen.
    public static func frame(barSize: CGSize, selection: CGRect?, pointer: CGPoint, visibleFrame screen: CGRect) -> CGRect {
        let anchorX: CGFloat
        let above: CGFloat
        let below: CGFloat
        if let selection, selection.width > 0 || selection.height > 0 {
            anchorX = min(max(pointer.x, selection.minX), selection.maxX)
            above = selection.minY - gap - barSize.height
            below = selection.maxY + gap
        } else {
            anchorX = pointer.x
            above = pointer.y - pointerOffset - barSize.height
            below = pointer.y + pointerOffset * 2
        }

        let y = above >= screen.minY ? above : below
        var x = anchorX - barSize.width / 2
        x = min(max(x, screen.minX), screen.maxX - barSize.width)
        let clampedY = min(max(y, screen.minY), screen.maxY - barSize.height)
        return CGRect(origin: CGPoint(x: x, y: clampedY), size: barSize)
    }
}
