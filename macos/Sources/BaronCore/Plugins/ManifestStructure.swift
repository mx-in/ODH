import Foundation

/// Checks a manifest's structure the way `packages/api/schema/manifest-1.json` does, reporting the same
/// JSON Pointers. The shared corpus in `packages/api/test/corpus` keeps the two in step.
public enum ManifestStructure {
    public static func check(_ manifest: JSONValue) -> [ManifestIssue] {
        var issues: [ManifestIssue] = []
        Shapes.manifest.check(manifest, at: JSONPointer(), into: &issues)
        return issues
    }
}

/// A regular expression from the schema. JSON Schema patterns are ECMAScript; these are written so ICU reads them
/// the same way, except that ICU's `$` also matches before a final newline, which `matches` rules out.
struct SchemaPattern: @unchecked Sendable {
    let source: String
    private let regex: NSRegularExpression

    init(_ source: String) {
        self.source = source
        regex = try! NSRegularExpression(pattern: source)
    }

    func matches(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return false }
        return !source.hasSuffix("$") || match.range.upperBound == range.upperBound
    }
}

indirect enum Shape: Sendable {
    case string(minLength: Int = 0, maxLength: Int? = nil, patterns: [SchemaPattern] = [], values: [String]? = nil, expected: String? = nil)
    case integer(minimum: Int)
    case number(exclusiveMinimum: Double? = nil)
    case boolean
    case anything
    case array(of: Shape, minItems: Int = 0, maxItems: Int? = nil, unique: Bool = false)
    case object(fields: [String: Shape], required: [String] = [], minProperties: Int = 0)
    /// Passes when one of the shapes passes. When only one shape takes the value's JSON type, its errors are reported.
    case either([Shape], expected: String)
    case preference

    func check(_ value: JSONValue, at pointer: JSONPointer, into issues: inout [ManifestIssue]) {
        let here = pointer.description
        switch self {
        case .anything:
            return

        case let .string(minLength, maxLength, patterns, values, expected):
            guard case .string(let text) = value else { return issues.append(.init(here, "must be a string")) }
            if let values, !values.contains(text) {
                return issues.append(.init(here, "must be one of \(values.joined(separator: ", "))"))
            }
            let length = text.unicodeScalars.count
            if length < minLength { issues.append(.init(here, minLength == 1 ? "must not be empty" : "must be at least \(minLength) characters")) }
            if let maxLength, length > maxLength { issues.append(.init(here, "must be at most \(maxLength) characters")) }
            if patterns.contains(where: { !$0.matches(text) }) { issues.append(.init(here, "must be \(expected ?? "in the documented format")")) }

        case .integer(let minimum):
            guard case .number(let n) = value, value.typeName == "integer" else { return issues.append(.init(here, "must be a whole number")) }
            if n < Double(minimum) { issues.append(.init(here, "must be at least \(minimum)")) }

        case .number(let exclusiveMinimum):
            guard case .number(let n) = value else { return issues.append(.init(here, "must be a number")) }
            if let exclusiveMinimum, n <= exclusiveMinimum { issues.append(.init(here, "must be more than \(exclusiveMinimum.formatted())")) }

        case .boolean:
            guard case .bool = value else { return issues.append(.init(here, "must be true or false")) }

        case let .array(item, minItems, maxItems, unique):
            guard case .array(let items) = value else { return issues.append(.init(here, "must be a list")) }
            if items.count < minItems { issues.append(.init(here, minItems == 1 ? "must not be empty" : "must have at least \(minItems) items")) }
            if let maxItems, items.count > maxItems { issues.append(.init(here, "must have at most \(maxItems) items")) }
            if unique, Set(items.indices.map { i in items.firstIndex(of: items[i])! }).count != items.count {
                issues.append(.init(here, "must not repeat an item"))
            }
            for (index, element) in items.enumerated() {
                item.check(element, at: pointer / index, into: &issues)
            }

        case let .object(fields, required, minProperties):
            guard case .object(let members) = value else { return issues.append(.init(here, "must be an object")) }
            Self.checkMembers(members, fields: fields, required: required, at: pointer, into: &issues)
            if members.count < minProperties { issues.append(.init(here, "must not be empty")) }

        case let .either(shapes, expected):
            var attempts: [[ManifestIssue]] = []
            for shape in shapes {
                var found: [ManifestIssue] = []
                shape.check(value, at: pointer, into: &found)
                if found.isEmpty { return }
                attempts.append(found)
            }
            let sameType = zip(shapes, attempts).filter { $0.0.accepts(typeOf: value) }
            if sameType.count == 1, let only = sameType.first {
                issues += only.1
            } else {
                issues.append(.init(here, "must be \(expected)"))
            }

        case .preference:
            Shapes.checkPreference(value, at: pointer, into: &issues)
        }
    }

    /// Whether the value has the JSON type this shape expects.
    func accepts(typeOf value: JSONValue) -> Bool {
        switch (self, value) {
        case (.anything, _), (.either, _), (.string, .string), (.integer, .number), (.number, .number),
             (.boolean, .bool), (.array, .array), (.object, .object), (.preference, .object):
            true
        default:
            false
        }
    }

    static func checkMembers(_ members: [String: JSONValue], fields: [String: Shape], required: [String], at pointer: JSONPointer, into issues: inout [ManifestIssue]) {
        for name in required where members[name] == nil {
            issues.append(.init((pointer / name).description, "is required"))
        }
        for (name, member) in members.sorted(by: { $0.key < $1.key }) {
            guard let shape = fields[name] else {
                issues.append(.init((pointer / name).description, "is not a known field"))
                continue
            }
            shape.check(member, at: pointer / name, into: &issues)
        }
    }
}

/// The schema's definitions, in the same order and with the same patterns.
enum Shapes {
    static let identifier = Shape.string(maxLength: 64, patterns: [SchemaPattern("^[A-Za-z_$][A-Za-z0-9_$]*$")], expected: "a JavaScript identifier, such as lookUp")
    static let label = Shape.string(minLength: 1)
    static let shortLabel = Shape.string(minLength: 1, maxLength: 100)
    static let text = Shape.string(maxLength: 500)
    static let version = Shape.string(maxLength: 64, patterns: [SchemaPattern(#"^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"#)], expected: "a semantic version, such as 1.2.0")
    static let locale = Shape.string(patterns: [SchemaPattern("^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$")], expected: "a BCP 47 language tag, such as en or zh-Hans")
    static let pathPattern = SchemaPattern(#"^(?!(?:.*/)?\.{1,2}(?:/|$))(?:[A-Za-z0-9_@.-]+/)*[A-Za-z0-9_@.-]+$"#)
    static func path(ending suffix: String, _ kind: String) -> Shape {
        .string(maxLength: 255, patterns: [pathPattern, SchemaPattern("\\.\(suffix)$")], expected: "a path inside the package to \(kind), with no . or .. parts")
    }
    static let svgPath = path(ending: "svg", "an SVG file")

    static let fixedPermissions = ["context.sentence", "context.paragraph", "context.page", "context.window", "clipboard.read", "selection.replace", "secrets", "code.dynamic"]
    static let networkPattern = SchemaPattern(#"^network:(?:https?://)?(?:\*\.)?(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*|\[[0-9a-f:.]+\])(?::[0-9]{1,5})?$"#)
    static let permissionExpected = "a known permission, or network: followed by a host such as dict.cn or *.youdao.com"
    static let permission = Shape.either([.string(values: fixedPermissions), .string(patterns: [networkPattern])], expected: permissionExpected)
    static let optionalPermission = Shape.either([permission, .string(values: ["network:*"])], expected: permissionExpected)

    static let appID = Shape.string(minLength: 1, maxLength: 255)
    static let appMatch = Shape.either([appID, .object(fields: ["macos": appID, "windows": appID, "linux": appID], minProperties: 1)], expected: "a bundle ID, or an object with macos, windows or linux IDs")

    static let when = Shape.object(fields: [
        "minLength": .integer(minimum: 0),
        "maxLength": .integer(minimum: 1),
        "regex": .string(minLength: 1, maxLength: 1000),
        "contentTypes": .array(of: .string(values: ["word", "url", "email", "number", "text"]), minItems: 1, unique: true),
        "apps": .array(of: appMatch, minItems: 1),
        "excludeApps": .array(of: appMatch, minItems: 1),
        "editable": .boolean,
    ])

    static let action = Shape.object(fields: [
        "id": identifier,
        "run": identifier,
        "title": shortLabel,
        "icon": svgPath,
        "when": when,
        "needs": .array(of: .string(values: ["sentence", "paragraph", "page", "window"]), unique: true),
        "autoRun": .string(values: ["allowed", "never"]),
    ], required: ["id", "title"])

    static let manifest = Shape.object(fields: [
        "$schema": .string(),
        "id": .string(maxLength: 128, patterns: [SchemaPattern(#"^[a-z0-9]+(?:-[a-z0-9]+)*(?:\.[a-z0-9]+(?:-[a-z0-9]+)*)+$"#)], expected: "lowercase reverse-DNS, such as org.example.plugin"),
        "name": shortLabel,
        "description": .string(minLength: 1, maxLength: 500),
        "version": version,
        "apiVersion": .integer(minimum: 1),
        "author": .string(minLength: 1, maxLength: 200),
        "homepage": .string(maxLength: 2000, patterns: [SchemaPattern(#"^https?://\S+$"#)], expected: "an http or https URL"),
        "license": .string(minLength: 1, maxLength: 100),
        "defaultLocale": locale,
        "main": path(ending: "js", "the built JavaScript"),
        "icon": svgPath,
        "platforms": .array(of: .string(values: ["macos", "windows", "linux"]), minItems: 1, unique: true),
        "minBaronVersion": version,
        "permissions": .array(of: permission, unique: true),
        "optionalPermissions": .array(of: optionalPermission, unique: true),
        "preferences": .array(of: .preference),
        "settingsPage": path(ending: "html", "an HTML page"),
        "settingsView": identifier,
        "actions": .array(of: action, minItems: 1, maxItems: 50),
    ], required: ["id", "name", "description", "version", "apiVersion", "main", "actions"])

    // MARK: Preferences

    static let option = Shape.object(fields: ["value": .string(minLength: 1), "title": shortLabel, "subtitle": text], required: ["value", "title"])
    static let required = Shape.boolean
    static let regexText = Shape.string(minLength: 1, maxLength: 1000)

    /// Fields each type adds to `id`, `type`, `title` and `description`.
    static let preferenceFields: [String: [String: Shape]] = [
        "text": ["required": required, "default": .string(), "placeholder": text, "multiline": .boolean, "pattern": regexText, "maxLength": .integer(minimum: 1)],
        "number": ["required": required, "default": .number(), "min": .number(), "max": .number(), "step": .number(exclusiveMinimum: 0)],
        "checkbox": ["required": required, "default": .boolean, "label": text],
        "dropdown": ["required": required, "default": .string(), "options": .array(of: option), "optionsFrom": identifier, "dependsOn": .array(of: identifier, unique: true)],
        "checklist": ["required": required, "default": .array(of: .string(), unique: true), "options": .array(of: option), "optionsFrom": identifier, "dependsOn": .array(of: identifier, unique: true)],
        "list": ["required": required, "default": .array(of: .string()), "itemPlaceholder": text, "itemPattern": regexText, "maxItems": .integer(minimum: 1)],
        "secret": ["required": required, "placeholder": text],
        "file": ["required": required, "extensions": .array(of: .string(patterns: [SchemaPattern("^[A-Za-z0-9]+$")], expected: "an extension without the dot, such as json"), minItems: 1, unique: true)],
        "directory": ["required": required],
        "app": ["required": required, "default": .string(minLength: 1)],
        "button": ["run": identifier, "label": shortLabel],
        "heading": [:],
    ]
    static let preferenceRequired: [String: [String]] = ["button": ["run", "label"]]
    static let preferenceBase: [String: Shape] = ["id": identifier, "type": .string(values: preferenceFields.keys.sorted()), "title": text, "description": text]

    static func checkPreference(_ value: JSONValue, at pointer: JSONPointer, into issues: inout [ManifestIssue]) {
        guard case .object(let members) = value else { return issues.append(.init(pointer.description, "must be an object")) }
        guard case .string(let type)? = members["type"], let typeFields = preferenceFields[type] else {
            // Without a known type nothing else can be checked, as in the schema.
            let base = members.filter { preferenceBase[$0.key] != nil }
            return Shape.checkMembers(base, fields: preferenceBase, required: ["id", "type", "title"], at: pointer, into: &issues)
        }
        let fields = preferenceBase.merging(typeFields) { base, _ in base }
        Shape.checkMembers(members, fields: fields, required: ["id", "type", "title"] + (preferenceRequired[type] ?? []), at: pointer, into: &issues)
        if typeFields["optionsFrom"] != nil, (members["options"] == nil) == (members["optionsFrom"] == nil) {
            issues.append(.init(pointer.description, "needs either options or optionsFrom, not both"))
        }
    }
}
