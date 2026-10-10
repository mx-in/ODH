import BaronCore
import Foundation

/// Where Baron keeps each plugin's data: `PluginData/<id>/` (preferences, storage, grants) in Application Support,
/// and `PluginCache/<id>/` in Caches, which macOS may purge. Plugin code never sees a path. Design: 05-storage.md#on-disk
public struct PluginDataLocation: Sendable {
    public let dataRoot: URL
    public let cacheRoot: URL

    public init(dataRoot: URL, cacheRoot: URL) {
        self.dataRoot = dataRoot
        self.cacheRoot = cacheRoot
    }

    public static var standard: PluginDataLocation {
        let fm = FileManager.default
        return PluginDataLocation(
            dataRoot: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Baron.name).appendingPathComponent("PluginData"),
            cacheRoot: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(Baron.name).appendingPathComponent("PluginCache"))
    }

    /// A throwaway location, for tests.
    public static func temporary() -> PluginDataLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("baron-data-\(UUID().uuidString)")
        return PluginDataLocation(dataRoot: root.appendingPathComponent("PluginData"), cacheRoot: root.appendingPathComponent("PluginCache"))
    }

    /// The plugin's data folder, created if missing.
    public func dataFolder(for pluginID: String) throws -> URL {
        try folder(dataRoot, pluginID)
    }

    /// The plugin's cache folder, created if missing.
    public func cacheFolder(for pluginID: String) throws -> URL {
        try folder(cacheRoot, pluginID)
    }

    private func folder(_ root: URL, _ pluginID: String) throws -> URL {
        guard !pluginID.isEmpty, !pluginID.contains("/"), !pluginID.hasPrefix(".") else { throw HostError.invalidArgument("Bad plugin id \(pluginID)") }
        let url = root.appendingPathComponent(pluginID, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
