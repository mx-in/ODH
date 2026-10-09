/// Everything the user can change. Stored as JSON; missing keys fall back to defaults,
/// so settings saved by an older build still load.
public struct BaronSettings: Codable, Equatable, Sendable {
    public var isPaused: Bool
    public var excludedApps: [String]
    public var searchTemplate: String
    public var retrievalRules: AppRetrievalRules

    public init(
        isPaused: Bool = false,
        excludedApps: [String] = ExcludedAppRule.defaults.sorted(),
        searchTemplate: String = SearchAction.defaultTemplate,
        retrievalRules: AppRetrievalRules = AppRetrievalRules()
    ) {
        self.isPaused = isPaused
        self.excludedApps = excludedApps
        self.searchTemplate = searchTemplate
        self.retrievalRules = retrievalRules
    }

    public init(from decoder: Decoder) throws {
        let defaults = BaronSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? defaults.isPaused
        excludedApps = try container.decodeIfPresent([String].self, forKey: .excludedApps) ?? defaults.excludedApps
        searchTemplate = try container.decodeIfPresent(String.self, forKey: .searchTemplate) ?? defaults.searchTemplate
        retrievalRules = try container.decodeIfPresent(AppRetrievalRules.self, forKey: .retrievalRules) ?? defaults.retrievalRules
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
