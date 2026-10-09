import AppKit
import BaronCore

/// Shows the bar next to a selection and hides it when the user moves on.
@MainActor
public final class ActionBarController {
    public var onSelect: ((BarItem) -> Void)?
    public private(set) var isVisible = false

    private let panel = ActionBarPanel()
    private let content = ActionBarView()
    private let dismissal = BarDismissMonitor()

    public init() {
        panel.contentView = content
        content.onSelect = { [weak self] item in
            self?.hide()
            self?.onSelect?(item)
        }
        dismissal.onDismiss = { [weak self] in self?.hide() }
    }

    /// - Parameters:
    ///   - selection: the selection's bounds (top-left origin), when the app reports them.
    ///   - pointer: the pointer location (top-left origin).
    public func show(_ items: [BarItem], selection: CGRect?, pointer: CGPoint) {
        guard !items.isEmpty else { return hide() }
        content.show(items)
        let size = content.fittingSize
        let screen = ScreenGeometry.visibleFrame(containing: pointer)
        let frame = BarPlacement.frame(barSize: size, selection: selection, pointer: pointer, visibleFrame: screen)
        panel.setFrame(ScreenGeometry.appKit(fromTopLeft: frame), display: true)
        panel.orderFrontRegardless()
        isVisible = true
        dismissal.start()
    }

    public func hide() {
        guard isVisible else { return }
        dismissal.stop()
        panel.orderOut(nil)
        isVisible = false
    }
}
