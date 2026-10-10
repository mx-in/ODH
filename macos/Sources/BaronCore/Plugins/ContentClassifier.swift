import Foundation

/// Sorts a trimmed selection into the `contentTypes` a `when` rule can ask for. Any non-empty text is `text`.
public enum ContentClassifier {
    /// Letters only, with apostrophes or hyphens between letters: "fox", "don't", "well-known", "Füchse", "狐狸".
    static let word = SchemaPattern(#"^\p{L}[\p{L}\p{M}]*(?:['’\-][\p{L}\p{M}]+)*$"#)
    static let email = SchemaPattern(#"^[^\s@]+@[^\s@]+\.[^\s@]+$"#)
    /// An optional sign, digits with optional thousands separators, an optional fraction and percent sign.
    static let number = SchemaPattern(#"^[+\-−]?(?:\d+|\d{1,3}(?:[,  ]\d{3})+)(?:[.,]\d+)?%?$"#)
    static let link = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public static func types(of text: String) -> Set<ContentType> {
        guard !text.isEmpty else { return [] }
        var types: Set<ContentType> = [.text]
        if word.matches(text) { types.insert(.word) }
        if number.matches(text) { types.insert(.number) }
        if email.matches(text) { types.insert(.email) } else if isURL(text) { types.insert(.url) }
        return types
    }

    /// The whole text is one http or https link (a bare domain such as example.com counts).
    static func isURL(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = link.firstMatch(in: text, range: range), match.range == range,
              let scheme = match.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

extension WhenRules {
    func contentMatches(_ text: String) -> Bool {
        guard let contentTypes else { return true }
        return !ContentClassifier.types(of: text).isDisjoint(with: contentTypes)
    }
}
