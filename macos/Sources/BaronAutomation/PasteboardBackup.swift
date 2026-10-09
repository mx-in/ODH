import AppKit

/// Saves every item and type on the general pasteboard so a UI test can put it back.
public struct PasteboardBackup {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    public init() {
        items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { types[type] = data }
            }
            return types
        }
    }

    public func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let restored = items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
