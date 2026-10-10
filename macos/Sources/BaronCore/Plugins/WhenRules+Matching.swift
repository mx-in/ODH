import Foundation

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
        lengthMatches(input.text)
    }

    /// Lengths count UTF-16 code units, like JavaScript's `string.length`.
    func lengthMatches(_ text: String) -> Bool {
        let length = text.utf16.count
        return length >= (minLength ?? 0) && length <= (maxLength ?? .max)
    }
}
