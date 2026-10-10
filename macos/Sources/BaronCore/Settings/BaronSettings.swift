/// Everything the user can change. Stored as JSON; missing keys fall back to defaults,
/// so settings saved by an older build still load.
public struct BaronSettings: Codable, Equatable, Sendable {
    public var isPaused: Bool
    public var excludedApps: [String]
    public var searchTemplate: String
    public var retrievalRules: AppRetrievalRules
    /// Plugins the user switched off: installed, data kept, no actions on the bar.
    public var disabledPlugins: [String]
    /// Bundled plugins already offered at first launch, whatever the answer.
    public var offeredBundledPlugins: [String]
    public var bar: BarArrangement
    /// Lets `baron dev` load and reload plugins through a socket only this user can open.
    public var developerMode: Bool

    public init(
        isPaused: Bool = false,
        excludedApps: [String] = ExcludedAppRule.defaults.sorted(),
        searchTemplate: String = SearchAction.defaultTemplate,
        retrievalRules: AppRetrievalRules = AppRetrievalRules(),
        disabledPlugins: [String] = [],
        offeredBundledPlugins: [String] = [],
        bar: BarArrangement = BarArrangement(),
        developerMode: Bool = false
    ) {
        self.isPaused = isPaused
        self.excludedApps = excludedApps
        self.searchTemplate = searchTemplate
        self.retrievalRules = retrievalRules
        self.disabledPlugins = disabledPlugins
        self.offeredBundledPlugins = offeredBundledPlugins
        self.bar = bar
        self.developerMode = developerMode
    }

    public init(from decoder: Decoder) throws {
        let defaults = BaronSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? defaults.isPaused
        excludedApps = try container.decodeIfPresent([String].self, forKey: .excludedApps) ?? defaults.excludedApps
        searchTemplate = try container.decodeIfPresent(String.self, forKey: .searchTemplate) ?? defaults.searchTemplate
        retrievalRules = try container.decodeIfPresent(AppRetrievalRules.self, forKey: .retrievalRules) ?? defaults.retrievalRules
        disabledPlugins = try container.decodeIfPresent([String].self, forKey: .disabledPlugins) ?? defaults.disabledPlugins
        offeredBundledPlugins = try container.decodeIfPresent([String].self, forKey: .offeredBundledPlugins) ?? defaults.offeredBundledPlugins
        bar = try container.decodeIfPresent(BarArrangement.self, forKey: .bar) ?? defaults.bar
        developerMode = try container.decodeIfPresent(Bool.self, forKey: .developerMode) ?? defaults.developerMode
    }

    public func isPluginEnabled(_ id: String) -> Bool {
        !disabledPlugins.contains(id)
    }

    public mutating func setPlugin(_ id: String, enabled: Bool) {
        disabledPlugins.removeAll { $0 == id }
        if !enabled { disabledPlugins.append(id); disabledPlugins.sort() }
    }

    /// Baron never shows its bar over itself, whatever the user removes from the list.
    public var effectiveExcludedApps: Set<String> {
        Set(excludedApps).union([Baron.bundleIdentifier])
    }

    public static func isValidSearchTemplate(_ template: String) -> Bool {
        SearchAction(template: template).url(for: "test") != nil
    }

    public mutating func exclude(_ bundleIdentifier: String) {
        guard !excludedApps.contains(bundleIdentifier) else { return }
        excludedApps.append(bundleIdentifier)
        excludedApps.sort()
    }

    public mutating func include(_ bundleIdentifier: String) {
        excludedApps.removeAll { $0 == bundleIdentifier }
    }
}
