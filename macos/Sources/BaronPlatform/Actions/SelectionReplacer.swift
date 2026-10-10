import AppKit
import ApplicationServices

/// Replaces the selected text in the frontmost app: through Accessibility where the field takes it,
/// otherwise by pasting, with the user's clipboard put back afterwards.
@MainActor
public enum SelectionReplacer {
    public static func replace(with text: String) {
        if let app = FocusedElementReader.frontmostApplication,
           let focused = FocusedElementReader.focusedElement(in: AXElement.application(pid: app.processIdentifier)),
           focused.isSettable(kAXSelectedTextAttribute),
           focused.set(kAXSelectedTextAttribute, to: text as CFString) {
            return
        }
        paste(text)
    }

    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount
        postCommandV()
        // Give the app time to read the clipboard, then restore it unless someone else wrote meanwhile.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pasteboard.changeCount == ours else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
