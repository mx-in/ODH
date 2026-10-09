import Foundation

/// One field the probe tried to read, how long it took, and what came back.
public struct ProbeReading: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case ok
        case missing
    }

    public var field: String
    public var status: Status
    public var value: String?
    public var milliseconds: Double

    public init(field: String, value: String?, milliseconds: Double) {
        self.field = field
        self.value = value
        self.status = (value?.isEmpty == false) ? .ok : .missing
        self.milliseconds = milliseconds
    }
}

/// Everything one probe run found for one app.
public struct ProbeReport: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String
    public var readings: [ProbeReading]

    public init(appName: String, bundleIdentifier: String, readings: [ProbeReading] = []) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.readings = readings
    }

    /// Runs `read`, times it, and records the result under `field`.
    public mutating func record(_ field: String, _ read: () -> String?) {
        let clock = ContinuousClock()
        var value: String?
        let elapsed = clock.measure { value = read() }
        readings.append(ProbeReading(field: field, value: value, milliseconds: elapsed.milliseconds))
    }

    public mutating func record(_ field: String, value: String?, milliseconds: Double) {
        readings.append(ProbeReading(field: field, value: value, milliseconds: milliseconds))
    }

    /// A fixed-width table for the terminal. Values are cut to `valueWidth` characters on one line.
    public func table(valueWidth: Int = 70) -> String {
        let fieldWidth = max(5, readings.map(\.field.count).max() ?? 0)
        var lines = ["\(appName) (\(bundleIdentifier))", ""]
        lines.append(pad("field", fieldWidth) + "  status    ms  value")
        for reading in readings {
            let ms = String(format: "%5.1f", reading.milliseconds)
            let value = ProbeReport.oneLine(reading.value ?? "", width: valueWidth)
            lines.append(pad(reading.field, fieldWidth) + "  " + pad(reading.status.rawValue, 7) + " " + ms + "  " + value)
        }
        return lines.joined(separator: "\n")
    }

    static func oneLine(_ text: String, width: Int) -> String {
        let flat = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: "⏎")
        return flat.count > width ? String(flat.prefix(width - 1)) + "…" : flat
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}

extension Duration {
    public var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
