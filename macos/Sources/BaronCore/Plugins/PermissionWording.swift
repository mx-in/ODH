/// Permissions in plain words, for the install sheet and run-time prompts. Design: 04-permissions-and-security.md
public enum PermissionWording {
    /// What the plugin may do, as a sentence fragment starting with a verb: "connect to dict.cn".
    public static func phrase(_ permission: PluginPermission) -> String {
        switch permission {
        case .contextSentence: "read the sentence around what you select"
        case .contextParagraph: "read the paragraph around what you select"
        case .contextPage: "see the web page address"
        case .contextWindow: "see the window title and file name"
        case .clipboardRead: "read your clipboard"
        case .selectionReplace: "replace the text you select"
        case .secrets: "store passwords and keys in your Keychain"
        case .codeDynamic: "run code it downloads"
        case .anyNetwork: "connect to other websites"
        case .network(let pattern): "connect to " + place(pattern)
        }
    }

    static func place(_ pattern: NetworkPattern) -> String {
        if pattern.isLoopback { return "apps on this Mac (\(pattern.host)\(pattern.port.map { ":\($0)" } ?? ""))" }
        var text = pattern.wildcard ? "any site under \(pattern.host)" : pattern.host
        if let port = pattern.port { text += " on port \(port)" }
        if pattern.scheme == "http" { text += " without encryption" }
        return text
    }

    /// The prompt's title: “ODH” wants to connect to dict.cn.
    public static func promptTitle(pluginName: String, permission: PluginPermission) -> String {
        "“\(pluginName)” wants to \(phrase(permission))."
    }

    /// The install sheet's lists.
    public struct Summary: Equatable, Sendable {
        public var reads: [String] = []
        public var connectsTo: [String] = []
        public var can: [String] = []
        public var stores: [String] = []
        /// Things the user should know before installing, such as downloaded code.
        public var disclosures: [String] = []

        public var isEmpty: Bool { reads.isEmpty && connectsTo.isEmpty && can.isEmpty && stores.isEmpty && disclosures.isEmpty }
    }

    public static func summary(of manifest: PluginManifest) -> Summary {
        var summary = Summary()
        func add(_ permission: PluginPermission, optional: Bool) {
            let words = sentence(phrase(permission), optional: optional)
            switch permission {
            case .contextSentence, .contextParagraph, .contextPage, .contextWindow, .clipboardRead: summary.reads.append(words)
            // Host names keep their case: "dict.cn", not "Dict.cn".
            case .network, .anyNetwork: summary.connectsTo.append(optional ? words : place(of: permission))
            case .selectionReplace: summary.can.append(words)
            case .secrets: summary.stores.append(words)
            case .codeDynamic: summary.disclosures.append("Runs code it downloads, which keeps the plugin's permissions.")
            }
        }
        for permission in manifest.permissions.compactMap(PluginPermission.init) { add(permission, optional: false) }
        for permission in manifest.optionalPermissions.compactMap(PluginPermission.init) { add(permission, optional: true) }
        return summary
    }

    static func place(of permission: PluginPermission) -> String {
        if case .network(let pattern) = permission { return place(pattern) }
        return phrase(permission)
    }

    static func sentence(_ fragment: String, optional: Bool) -> String {
        let text = optional ? "may ask to " + fragment : fragment
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
