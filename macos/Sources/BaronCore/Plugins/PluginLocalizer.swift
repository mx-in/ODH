import Foundation

/// Resolves a plugin's `%key%` strings for the user: each preferred language in order, dropping subtags
/// (`zh-Hans-CN`, then `zh-Hans`, then `zh`), then the plugin's `defaultLocale`, then the key itself.
public struct PluginLocalizer: Sendable {
    private let tables: [[String: String]]

    /// `tables` maps a language tag to its strings, as in `locales/<tag>.json`.
    public init(tables: [String: [String: String]], defaultLocale: String?, preferredLanguages: [String]) {
        var order: [String] = []
        for language in preferredLanguages {
            var parts = language.split(separator: "-").map(String.init)
            while !parts.isEmpty {
                order.append(parts.joined(separator: "-"))
                parts.removeLast()
            }
        }
        if let defaultLocale { order.append(defaultLocale) }
        var seen = Set<String>()
        self.tables = order.filter { seen.insert($0).inserted }.compactMap { tables[$0] }
    }

    /// Loads every `locales/*.json` in the package.
    public init(package: URL, defaultLocale: String?, preferredLanguages: [String] = Locale.preferredLanguages) {
        let folder = package.appendingPathComponent("locales")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let tags = files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }
        let tables = Dictionary(uniqueKeysWithValues: tags.compactMap { tag in PluginLocales.table(for: tag, in: package).map { (tag, $0) } })
        self.init(tables: tables, defaultLocale: defaultLocale, preferredLanguages: preferredLanguages)
    }

    /// The text to show for a manifest string: itself unless it is `%key%`.
    public func resolve(_ text: String) -> String {
        guard let key = PluginLocales.key(in: text) else { return text }
        return tables.lazy.compactMap { $0[key] }.first ?? key
    }
}
