import Foundation

/// What host services ask of macOS. The app implements it with AppKit and Accessibility, so BaronRuntime stays free
/// of both; tests record the calls.
public protocol SystemActions: Sendable {
    func readClipboard() async -> String
    func writeClipboard(_ text: String) async
    /// Replaces the current selection; false when the selection can't be replaced.
    func replaceSelection(with text: String) async -> Bool
    func open(_ url: URL) async
    func openSettings(pluginID: String) async
}
