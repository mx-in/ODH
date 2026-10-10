import AppKit
import BaronPlatform
import BaronRuntime

/// Shows plugin toasts (and Baron's messages about plugins) near the last selection.
final class ToastPresenter: PluginPresenter, @unchecked Sendable {
    @MainActor private let panel = ToastPanel()
    @MainActor var anchor: CGPoint = .zero

    func toast(_ message: String, kind: String, from plugin: RuntimePlugin) async {
        await show(message, kind: ToastPanel.Kind(rawValue: kind) ?? .info)
    }

    @MainActor
    func show(_ message: String, kind: ToastPanel.Kind) {
        panel.show(message, kind: kind, near: anchor)
    }
}
