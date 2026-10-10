import Foundation

/// A plugin's `manifest.json`, decoded after `ManifestStructure` found no issues.
/// Field meanings: docs/design/plugin-platform/01-package-and-manifest.md
public struct PluginManifest: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var version: String
    public var apiVersion: Int
    public var author: String?
    public var homepage: String?
    public var license: String?
    public var defaultLocale: String?
    public var main: String
    public var icon: String?
    /// All platforms when the manifest leaves it out.
    public var platforms: [PluginPlatform]
    public var minBaronVersion: String?
    public var permissions: [String]
    public var optionalPermissions: [String]
    public var preferences: [Preference]
    public var settingsPage: String?
    public var settingsView: String?
    public var actions: [Action]

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, apiVersion, author, homepage, license, defaultLocale, main, icon
        case platforms, minBaronVersion, permissions, optionalPermissions, preferences, settingsPage, settingsView, actions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        version = try c.decode(String.self, forKey: .version)
        apiVersion = try c.decode(Int.self, forKey: .apiVersion)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        homepage = try c.decodeIfPresent(String.self, forKey: .homepage)
        license = try c.decodeIfPresent(String.self, forKey: .license)
        defaultLocale = try c.decodeIfPresent(String.self, forKey: .defaultLocale)
        main = try c.decode(String.self, forKey: .main)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        platforms = try c.decodeIfPresent([PluginPlatform].self, forKey: .platforms) ?? PluginPlatform.allCases
        minBaronVersion = try c.decodeIfPresent(String.self, forKey: .minBaronVersion)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        optionalPermissions = try c.decodeIfPresent([String].self, forKey: .optionalPermissions) ?? []
        preferences = try c.decodeIfPresent([Preference].self, forKey: .preferences) ?? []
        settingsPage = try c.decodeIfPresent(String.self, forKey: .settingsPage)
        settingsView = try c.decodeIfPresent(String.self, forKey: .settingsView)
        actions = try c.decode([Action].self, forKey: .actions)
    }

    public struct Action: Decodable, Equatable, Sendable {
        public var id: String
        public var run: String?
        public var title: String
        public var icon: String?
        public var when: WhenRules?
        public var needs: [ContextField]?
        public var autoRun: AutoRun?

        /// The exported handler this action calls.
        public var handlerName: String { run ?? id }
    }

    public enum AutoRun: String, Decodable, Sendable {
        case allowed, never
    }
}

public enum PluginPlatform: String, Decodable, CaseIterable, Sendable {
    case macos, windows, linux
}

public enum ContextField: String, Codable, CaseIterable, Sendable {
    case sentence, paragraph, page, window

    /// The permission that grants this field.
    public var permission: String { "context.\(rawValue)" }
}

public enum ContentType: String, Decodable, CaseIterable, Sendable {
    case word, url, email, number, text
}

/// An app named in `apps` or `excludeApps`: a bundle ID, or one ID per platform.
public struct AppMatch: Decodable, Equatable, Sendable {
    public var ids: [PluginPlatform: String]

    public init(ids: [PluginPlatform: String]) {
        self.ids = ids
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let bundleID = try? c.decode(String.self) {
            ids = [.macos: bundleID]
        } else {
            let byName = try c.decode([String: String].self)
            ids = Dictionary(uniqueKeysWithValues: byName.compactMap { key, value in PluginPlatform(rawValue: key).map { ($0, value) } })
        }
    }
}

public struct WhenRules: Decodable, Equatable, Sendable {
    public var minLength: Int?
    public var maxLength: Int?
    public var regex: String?
    public var contentTypes: [ContentType]?
    public var apps: [AppMatch]?
    public var excludeApps: [AppMatch]?
    public var editable: Bool?

    public init(minLength: Int? = nil, maxLength: Int? = nil, regex: String? = nil, contentTypes: [ContentType]? = nil,
                apps: [AppMatch]? = nil, excludeApps: [AppMatch]? = nil, editable: Bool? = nil) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.regex = regex
        self.contentTypes = contentTypes
        self.apps = apps
        self.excludeApps = excludeApps
        self.editable = editable
    }
}

public enum PreferenceType: String, Decodable, CaseIterable, Sendable {
    case text, number, checkbox, dropdown, checklist, list, secret, file, directory, app, button, heading
}

public enum PreferenceValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case strings([String])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let bool = try? c.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? c.decode(Double.self) { self = .number(number) }
        else if let string = try? c.decode(String.self) { self = .string(string) }
        else { self = .strings(try c.decode([String].self)) }
    }
}

/// One declared preference. The structure check has already made sure each field belongs to `type`.
public struct Preference: Decodable, Equatable, Sendable {
    public var id: String
    public var type: PreferenceType
    public var title: String
    public var description: String?
    public var required: Bool?
    public var `default`: PreferenceValue?
    public var placeholder: String?
    public var multiline: Bool?
    public var pattern: String?
    public var maxLength: Int?
    public var min: Double?
    public var max: Double?
    public var step: Double?
    public var label: String?
    public var options: [Option]?
    public var optionsFrom: String?
    public var dependsOn: [String]?
    public var itemPlaceholder: String?
    public var itemPattern: String?
    public var maxItems: Int?
    public var extensions: [String]?
    public var run: String?

    public struct Option: Decodable, Equatable, Sendable, Hashable {
        public var value: String
        public var title: String
        public var subtitle: String?

        public init(value: String, title: String, subtitle: String? = nil) {
            self.value = value
            self.title = title
            self.subtitle = subtitle
        }
    }
}
