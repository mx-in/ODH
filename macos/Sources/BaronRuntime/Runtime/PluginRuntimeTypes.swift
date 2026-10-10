import BaronCore
import Foundation

/// The limits from the runtime design (02-runtime.md#limits-and-stuck-plugins); tests shorten them.
public struct RuntimeLimits: Sendable {
    public var load: Duration = .seconds(2)
    public var action: Duration = .seconds(10)
    public var options: Duration = .seconds(5)
    public var button: Duration = .seconds(10)
    public var lifecycle: Duration = .seconds(10)
    public var event: Duration = .seconds(5)
    /// Time inside one synchronous run of plugin code before the plugin counts as stuck.
    public var stuck: Duration = .seconds(10)
    public var idle: Duration = .seconds(60)
    public var strikes = 3
    public var strikeWindow: Duration = .seconds(600)

    public init() {}

    func timeLimit(for target: DispatchTarget) -> Duration {
        switch target {
        case .action: action
        case .options: options
        case .button: button
        case .lifecycle: lifecycle
        case .event: event
        }
    }
}

/// Where a plugin's code stands.
public enum PluginRuntimeState: Equatable, Sendable {
    /// Not loaded; loads on the next dispatch.
    case unloaded
    case ready
    /// Its code fails to load; fixed only by an update.
    case broken(String)
    /// Stuck or out of strikes; runs again only after the user re-enables it.
    case suspended(String)
}

/// A plugin the runtime can load: its manifest and package folder.
public struct RuntimePlugin: Sendable {
    public var manifest: PluginManifest
    public var package: URL

    public init(manifest: PluginManifest, package: URL) {
        self.manifest = manifest
        self.package = package
    }

    public var id: String { manifest.id }

    func bundleSource() throws -> String {
        let url = package.appendingPathComponent(manifest.main)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw HostError.notFound("Can't read \(manifest.main); build the plugin first")
        }
        return source
    }
}

/// Serves the host calls plugins make. The host router implements it.
public protocol HostCallHandler: Sendable {
    func handle(_ call: HostCall, from plugin: RuntimePlugin) async -> Result<JSONValue, HostError>
}
