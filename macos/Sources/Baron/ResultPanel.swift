import AppKit
import BaronWeb

/// The floating panel that shows a plugin page next to the selection. It takes clicks and scrolling without
/// taking focus from the source app; a click into a form field gives it keyboard focus until it closes.
/// Baron draws the header (the plugin's icon and name, pin, close) so users always know whose page they see.
/// Design: docs/design/plugin-platform/07-web-views.md#where-pages-appear
final class ResultPanel: NSPanel {
    static let headerHeight: CGFloat = 28
    static let defaultSize = CGSize(width: 420, height: 320)
    static let maximumHeight: CGFloat = 640

    var onClose: (() -> Void)?
    private(set) var isPinned = false
    private let header = NSVisualEffectView()
    private let pinButton = NSButton()
    private let closeButton = NSButton()
    private let nameLabel = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    let page: PluginWebView

    init(page: PluginWebView, name: String, icon image: NSImage?) {
        self.page = page
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .resizable], backing: .buffered, defer: true)
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        setAccessibilityIdentifier("baron.resultPanel")
        title = name

        let root = NSVisualEffectView()
        root.material = .popover
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        contentView = root

        header.material = .titlebar
        header.state = .active
        icon.image = image ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setAccessibilityIdentifier("resultPanel.title")
        configure(pinButton, symbol: "pin", label: "Pin", action: #selector(togglePin), identifier: "resultPanel.pin")
        configure(closeButton, symbol: "xmark", label: "Close", action: #selector(closePressed), identifier: "resultPanel.close")

        let row = NSStackView(views: [icon, nameLabel, NSView(), pinButton, closeButton])
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
        for view in [header, row, page] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
        header.addSubview(row)
        root.addSubview(header)
        root.addSubview(page)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            row.topAnchor.constraint(equalTo: header.topAnchor),
            row.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            page.topAnchor.constraint(equalTo: header.bottomAnchor),
            page.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The panel's size for a page of `content` size: the header on top, the height capped at 640 points.
    static func size(for content: CGSize) -> CGSize {
        CGSize(width: content.width, height: headerHeight + min(content.height, maximumHeight))
    }

    /// Grows or shrinks the page area to `height` (capped), keeping the panel's top edge where it is.
    func resizePage(to height: CGFloat) {
        let size = Self.size(for: CGSize(width: frame.width, height: height))
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true, animate: false)
    }

    @objc private func togglePin() {
        isPinned.toggle()
        pinButton.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: isPinned ? "Unpin" : "Pin")
        pinButton.setAccessibilityValue(isPinned ? "pinned" : "unpinned")
    }

    @objc private func closePressed() {
        onClose?()
    }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector, identifier: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityIdentifier(identifier)
    }
}
