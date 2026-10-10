/// How the user arranged the bar: an order (actions not in it go at the end, in their usual order), hidden actions,
/// and actions that run straight after a selection. Design: 10-install-and-lifecycle.md#actions-on-the-bar
public struct BarArrangement: Codable, Equatable, Sendable {
    public var order: [String]
    public var hidden: [String]
    /// Action → the apps it runs in automatically (bundle IDs); an empty list means every app.
    public var runOnSelection: [String: [String]]

    public init(order: [String] = [], hidden: [String] = [], runOnSelection: [String: [String]] = [:]) {
        self.order = order
        self.hidden = hidden
        self.runOnSelection = runOnSelection
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        hidden = try container.decodeIfPresent([String].self, forKey: .hidden) ?? []
        runOnSelection = try container.decodeIfPresent([String: [String]].self, forKey: .runOnSelection) ?? [:]
    }

    /// The bar's buttons: in the user's order, new ones at the end, hidden ones left out.
    public func arrange(_ items: [BarItem]) -> [BarItem] {
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated()
            .filter { !hidden.contains($0.element.id) }
            .sorted { a, b in
                switch (position[a.element.id], position[b.element.id]) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.offset < b.offset
                }
            }
            .map(\.element)
    }

    /// The action to run straight away for this selection, if the user chose one for this app.
    /// Only actions whose manifest allows it (`allowed`) qualify.
    public func automaticAction(among items: [BarItem], allowed: Set<String>, app bundleIdentifier: String?) -> String? {
        arrange(items).first { item in
            guard allowed.contains(item.id), let apps = runOnSelection[item.id] else { return false }
            return apps.isEmpty || bundleIdentifier.map(apps.contains) == true
        }?.id
    }

    /// Moves an action within the full list of actions shown in Settings.
    public mutating func move(_ id: String, by offset: Int, among all: [String]) {
        var list = arrange(all.map { BarItem(id: $0, title: $0, symbolName: nil) }).map(\.id)
        list += all.filter { hidden.contains($0) }
        guard let index = list.firstIndex(of: id) else { return }
        let target = max(0, min(list.count - 1, index + offset))
        list.remove(at: index)
        list.insert(id, at: target)
        order = list
    }
}
