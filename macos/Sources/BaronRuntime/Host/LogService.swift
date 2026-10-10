import BaronCore
import Foundation
import os

/// `host.log` and `console`: plugin lines go to the system log marked private, so they stay hidden unless a
/// developer turns on private logging. `sink` also gets every line (`baron dev` streams them, task-008).
public struct LogService: HostService {
    public let namespace = "log"
    public typealias Sink = @Sendable (_ pluginID: String, _ level: String, _ text: String) -> Void

    private static let logger = Logger(subsystem: "org.odh.baron", category: "plugin")
    private let sink: Sink?

    public init(sink: Sink? = nil) {
        self.sink = sink
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        let level: OSLogType
        switch method {
        case "debug": level = .debug
        case "info": level = .info
        case "warn": level = .default
        case "error": level = .error
        default: throw arguments.unknownMethod()
        }
        let text = try arguments.string(0)
        Self.logger.log(level: level, "\(plugin.id, privacy: .public) \(method, privacy: .public): \(text, privacy: .private)")
        sink?(plugin.id, method, text)
        return .null
    }
}
