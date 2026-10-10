import BaronCore
import Foundation

/// The values a user set in a plugin's settings, in `PluginData/<id>/preferences.json`; the plugin reads them as
/// `host.preferences`. Values not set fall back to the manifest's defaults. Secret, button and heading preferences
/// never appear here (secrets live in the Keychain). Design: 05-storage.md
public actor PreferencesStore {
    private let location: PluginDataLocation

    public init(location: PluginDataLocation) {
        self.location = location
    }

    /// The plugin's current values: saved ones over the manifest's defaults.
    public func values(for manifest: PluginManifest) -> [String: JSONValue] {
        var values = PreferenceDefaults.values(for: manifest)
        let kept = Set(manifest.preferences.filter { ![.secret, .button, .heading].contains($0.type) }.map(\.id))
        for (id, value) in saved(manifest.id) where kept.contains(id) { values[id] = value }
        return values
    }

    /// Saves one value; `nil` goes back to the default.
    public func set(_ id: String, to value: JSONValue?, pluginID: String) throws {
        var all = saved(pluginID)
        all[id] = value
        let url = try location.dataFolder(for: pluginID).appendingPathComponent("preferences.json")
        try JSONValue.object(all).jsonString.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    /// Only what the user changed, for the settings page.
    public func saved(_ pluginID: String) -> [String: JSONValue] {
        guard let url = try? location.dataFolder(for: pluginID).appendingPathComponent("preferences.json"),
              let data = try? Data(contentsOf: url), case .object(let all)? = try? JSONValue(data: data) else { return [:] }
        return all
    }
}
