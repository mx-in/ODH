import Foundation
import os

/// What `when` rules look at, read once per selection.
public struct WhenInput: Sendable {
    /// The selection with surrounding whitespace and line breaks removed.
    public var text: String
    public var bundleIdentifier: String?
    public var editable: Bool
    public var platform: PluginPlatform

    public init(text: String, bundleIdentifier: String?, editable: Bool, platform: PluginPlatform = .macos) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = bundleIdentifier
        self.editable = editable
        self.platform = platform
    }
}

extension WhenRules {
    /// True when every rule holds; a missing rule doesn't constrain. Checked in Swift before any plugin code runs.
    public func matches(_ input: WhenInput) -> Bool {
        lengthMatches(input.text) && regexMatches(input.text) && contentMatches(input.text)
    }

    /// Lengths count UTF-16 code units, like JavaScript's `string.length`.
    func lengthMatches(_ text: String) -> Bool {
        let length = text.utf16.count
        return length >= (minLength ?? 0) && length <= (maxLength ?? .max)
    }
}

extension WhenRules {
    /// Searches anywhere in the text, like JavaScript's `RegExp.prototype.test`. The validator has made sure
    /// the pattern means the same in JavaScript and ICU; a pattern that doesn't compile never matches.
    func regexMatches(_ text: String) -> Bool {
        guard let regex else { return true }
        guard let compiled = RegexCache.shared.regex(for: regex) else { return false }
        return compiled.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// Compiled `when` patterns, kept because rules run on every selection.
final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()
    private let compiled = OSAllocatedUnfairLock(initialState: [String: NSRegularExpression?]())

    func regex(for pattern: String) -> NSRegularExpression? {
        compiled.withLock { cache in
            if let hit = cache[pattern] { return hit }
            let regex = try? NSRegularExpression(pattern: pattern)
            cache[pattern] = regex
            return regex
        }
    }
}
