import Foundation

/// What an action asks the host to do. Performing it is the platform's job.
public enum ActionEffect: Equatable, Sendable {
    case copy(String)
    case openURL(URL)
    /// Replaces the selection in the source app.
    case replace(String)
}

/// An action that ships with Baron, as opposed to a plugin.
public protocol BuiltInAction: Sendable {
    var item: BarItem { get }
    func applies(to text: String) -> Bool
    func effect(for text: String) -> ActionEffect?
}

public struct CopyAction: BuiltInAction {
    public let item = BarItem(id: "builtin.copy", title: "Copy", symbolName: "doc.on.doc")

    public init() {}

    public func applies(to text: String) -> Bool { true }

    public func effect(for text: String) -> ActionEffect? { .copy(text) }
}

/// Opens a search URL built from a template with a `{query}` placeholder.
public struct SearchAction: BuiltInAction {
    public static let defaultTemplate = "https://www.google.com/search?q={query}"
    public static let placeholder = "{query}"
    public static let maxQueryLength = 500

    public let item = BarItem(id: "builtin.search", title: "Search", symbolName: "magnifyingglass")
    public var template: String

    public init(template: String = SearchAction.defaultTemplate) {
        self.template = template
    }

    public func applies(to text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= Self.maxQueryLength
    }

    public func effect(for text: String) -> ActionEffect? {
        guard let url = url(for: text) else { return nil }
        return .openURL(url)
    }

    public func url(for text: String) -> URL? {
        guard template.contains(Self.placeholder) else { return nil }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: Self.placeholder, with: encoded))
    }
}

/// Opens the first link found in the selection.
public struct OpenLinkAction: BuiltInAction {
    public let item = BarItem(id: "builtin.openLink", title: "Open Link", symbolName: "link")

    public init() {}

    public func applies(to text: String) -> Bool { link(in: text) != nil }

    public func effect(for text: String) -> ActionEffect? { link(in: text).map(ActionEffect.openURL) }

    public func link(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }
}

/// The built-in actions offered for a selection, in bar order.
public struct BuiltInActions: Sendable {
    public var actions: [any BuiltInAction]

    public init(searchTemplate: String = SearchAction.defaultTemplate) {
        actions = [CopyAction(), SearchAction(template: searchTemplate), OpenLinkAction()]
    }

    public func items(for text: String) -> [BarItem] {
        actions.filter { $0.applies(to: text) }.map(\.item)
    }

    public func effect(of itemID: String, for text: String) -> ActionEffect? {
        actions.first { $0.item.id == itemID }?.effect(for: text)
    }
}
