/// Plugin actions offered on the bar: each enabled plugin's actions, with titles already resolved for the user.
/// Their `when` rules are checked in Swift for every selection, before any plugin code runs.
public struct PluginActionCatalog: Sendable {
    public struct Entry: Sendable, Equatable {
        public var pluginID: String
        public var pluginName: String
        public var actionID: String
        public var title: String
        public var when: WhenRules?
        /// The manifest allows running it straight after a selection.
        public var mayAutoRun: Bool
        /// The context fields the action `needs` and its plugin's permissions grant.
        public var context: Set<ContextField>

        public init(pluginID: String, pluginName: String, actionID: String, title: String, when: WhenRules?, mayAutoRun: Bool = false,
                    context: Set<ContextField> = []) {
            self.pluginID = pluginID
            self.pluginName = pluginName
            self.actionID = actionID
            self.title = title
            self.when = when
            self.mayAutoRun = mayAutoRun
            self.context = context
        }

        public var itemID: String { PluginActionCatalog.itemID(pluginID: pluginID, actionID: actionID) }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Entries for each manifest's actions, in manifest order, with titles resolved by the plugin's localizer.
    public init(_ plugins: [(manifest: PluginManifest, localizer: PluginLocalizer)]) {
        entries = plugins.flatMap { manifest, localizer in
            manifest.actions.map { action in
                Entry(pluginID: manifest.id, pluginName: localizer.resolve(manifest.name), actionID: action.id,
                      title: localizer.resolve(action.title), when: action.when, mayAutoRun: action.autoRun == .allowed,
                      context: Set(action.needs ?? []).filter { manifest.permissions.contains($0.permission) })
            }
        }
    }

    public func items(for input: WhenInput) -> [BarItem] {
        entries.filter { $0.when?.matches(input) ?? !input.text.isEmpty }
            .map { BarItem(id: $0.itemID, title: $0.title, symbolName: nil) }
    }

    /// The context fields any of these bar items may receive: what is worth reading for a selection.
    public func contextFields(for items: [BarItem]) -> Set<ContextField> {
        let ids = Set(items.map(\.id))
        return entries.filter { ids.contains($0.itemID) }.reduce(into: []) { $0.formUnion($1.context) }
    }

    /// Whether any action may receive context, so reading it can matter at all.
    public var usesContext: Bool { entries.contains { !$0.context.isEmpty } }

    public func entry(forItemID id: String) -> Entry? {
        entries.first { $0.itemID == id }
    }

    static let prefix = "plugin:"

    static func itemID(pluginID: String, actionID: String) -> String {
        "\(prefix)\(pluginID)/\(actionID)"
    }
}
