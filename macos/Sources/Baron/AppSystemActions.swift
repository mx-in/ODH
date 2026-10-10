import AppKit
import BaronCore
import BaronPlatform
import BaronRuntime

/// What host services ask of macOS, done with AppKit and Accessibility on the main actor.
final class AppSystemActions: SystemActions, @unchecked Sendable {
    @MainActor var openSettingsWindow: (String) -> Void = { _ in }

    func readClipboard() async -> String {
        await MainActor.run { NSPasteboard.general.string(forType: .string) ?? "" }
    }

    func writeClipboard(_ text: String) async {
        await MainActor.run { ActionEffectPerformer.perform(.copy(text)) }
    }

    func replaceSelection(with text: String) async -> Bool {
        await MainActor.run {
            guard FocusedSelectionSource.current()?.isEditable == true else { return false }
            SelectionReplacer.replace(with: text)
            return true
        }
    }

    func open(_ url: URL) async {
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }

    func openSettings(pluginID: String) async {
        await MainActor.run { openSettingsWindow(pluginID) }
    }
}
