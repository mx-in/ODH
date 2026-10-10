import AppKit

/// A short message near the selection that never takes focus and fades out by itself.
@MainActor
public final class ToastPanel {
    public enum Kind: String { case info, success, error }

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    public init() {}

    /// `near` is a screen point with a top-left origin, such as the selection's top edge or the pointer.
    public func show(_ message: String, kind: Kind, near point: CGPoint) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = kind == .error ? .systemRed : .labelColor
        label.preferredMaxLayoutWidth = 320
        label.maximumNumberOfLines = 4
        label.setAccessibilityIdentifier("baron.toast.message")
        let symbol = NSImageView(image: NSImage(systemSymbolName: Self.symbol(kind), accessibilityDescription: kind.rawValue)!)
        symbol.contentTintColor = kind == .error ? .systemRed : kind == .success ? .systemGreen : .secondaryLabelColor
        let stack = NSStackView(views: [symbol, label])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor), stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor), stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        let size = stack.fittingSize

        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = background
        panel.setAccessibilityIdentifier("baron.toast")
        let screen = ScreenGeometry.visibleFrame(containing: point)
        let topLeft = CGRect(x: min(max(point.x - size.width / 2, screen.minX), screen.maxX - size.width),
                             y: max(point.y - size.height - 8, screen.minY), width: size.width, height: size.height)
        panel.setFrame(ScreenGeometry.appKit(fromTopLeft: topLeft), display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (kind == .error ? 4 : 2.5), execute: work)
    }

    private static func symbol(_ kind: Kind) -> String {
        switch kind {
        case .info: "info.circle"
        case .success: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }
}
