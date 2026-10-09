import AppKit
import BaronCore

/// The floating bar. It never becomes key or main, so the source app keeps focus
/// and its selection while the user clicks a button.
final class ActionBarPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        setAccessibilityIdentifier("baron.actionBar")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The bar's content: one borderless button per item on a translucent background.
final class ActionBarView: NSVisualEffectView {
    var onSelect: ((BarItem) -> Void)?
    private let stack = NSStackView()
    private var items: [BarItem] = []

    init() {
        super.init(frame: .zero)
        material = .popover
        state = .active
        blendingMode = .behindWindow
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ items: [BarItem]) {
        self.items = items
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in items.enumerated() {
            let button = NSButton(title: item.title, target: self, action: #selector(pressed(_:)))
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.font = .systemFont(ofSize: 12)
            if let symbol = item.symbolName {
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                button.imagePosition = .imageLeading
            }
            button.setAccessibilityIdentifier("baron.action.\(item.id)")
            stack.addArrangedSubview(button)
        }
    }

    @objc private func pressed(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onSelect?(items[sender.tag])
    }
}
