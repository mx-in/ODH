/// One problem with a plugin manifest. `pointer` is a JSON Pointer (RFC 6901) to the offending field;
/// for a missing or unknown field, to where that field is or would be. `@baron/api` uses the same convention.
public struct ManifestIssue: Equatable, Sendable, CustomStringConvertible {
    public var pointer: String
    public var message: String

    public init(_ pointer: String, _ message: String) {
        self.pointer = pointer
        self.message = message
    }

    public var description: String { "\(pointer.isEmpty ? "/" : pointer): \(message)" }
}

/// Builds JSON Pointers one step at a time.
public struct JSONPointer: Equatable, Sendable, CustomStringConvertible {
    public private(set) var description = ""

    public init() {}

    public static func / (pointer: JSONPointer, key: String) -> JSONPointer {
        var next = pointer
        next.description += "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
        return next
    }

    public static func / (pointer: JSONPointer, index: Int) -> JSONPointer {
        pointer / String(index)
    }
}
