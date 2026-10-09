import BaronCore
import Combine
import Foundation

/// Keeps `BaronSettings` in `UserDefaults` and publishes every change.
@MainActor
public final class SettingsStore: ObservableObject {
    static let key = "settings"

    @Published public var settings: BaronSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode(BaronSettings.self, from: data) {
            settings = stored
        } else {
            settings = BaronSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
