import Foundation

/// A plugin's translated strings: `locales/<language>.json`, each a flat map from key to text.
public enum PluginLocales {
    /// The key when `text` is a `%key%` reference, such as `%action.lookup%`.
    public static func key(in text: String) -> String? {
        guard text.count > 2, text.hasPrefix("%"), text.hasSuffix("%") else { return nil }
        let key = text.dropFirst().dropLast()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
        return key.unicodeScalars.allSatisfy(allowed.contains) && key.allSatisfy(\.isASCII) ? String(key) : nil
    }

    /// The strings for one language, or nil when the file is missing or isn't a flat map of strings.
    public static func table(for language: String, in package: URL) -> [String: String]? {
        let file = package.appendingPathComponent("locales").appendingPathComponent("\(language).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    /// Every user-visible string in the manifest, with its pointer.
    static func strings(in manifest: PluginManifest) -> [(JSONPointer, String)] {
        let root = JSONPointer()
        var found: [(JSONPointer, String)] = [(root / "name", manifest.name), (root / "description", manifest.description)]
        for (index, action) in manifest.actions.enumerated() {
            found.append((root / "actions" / index / "title", action.title))
        }
        for (index, preference) in manifest.preferences.enumerated() {
            let here = root / "preferences" / index
            let fields: [(String, String?)] = [("title", preference.title), ("description", preference.description), ("placeholder", preference.placeholder),
                                               ("label", preference.label), ("itemPlaceholder", preference.itemPlaceholder)]
            for case let (name, text?) in fields { found.append((here / name, text)) }
            for (position, option) in (preference.options ?? []).enumerated() {
                found.append((here / "options" / position / "title", option.title))
                if let subtitle = option.subtitle { found.append((here / "options" / position / "subtitle", subtitle)) }
            }
        }
        return found
    }
}

/// `%key%` strings need a default locale whose file has every key.
enum LocaleReferenceChecks {
    static func check(_ manifest: PluginManifest, package: URL) -> [ManifestIssue] {
        let references = PluginLocales.strings(in: manifest).compactMap { pointer, text in PluginLocales.key(in: text).map { (pointer, $0) } }
        guard let language = manifest.defaultLocale else {
            return references.isEmpty ? [] : [ManifestIssue("/defaultLocale", "is required when strings use %key%")]
        }
        guard let table = PluginLocales.table(for: language, in: package) else {
            return [ManifestIssue("/defaultLocale", "has no locales/\(language).json, or it isn't a map of strings")]
        }
        return references.compactMap { pointer, key in
            table[key] == nil ? ManifestIssue(pointer.description, "uses %\(key)%, which locales/\(language).json doesn't define") : nil
        }
    }
}
