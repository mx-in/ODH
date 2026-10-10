import Foundation
import JavaScriptCore

/// Patterns run as JavaScript in plugins and pages and as ICU in Baron, so each must compile in both.
/// JavaScript patterns are compiled with the `u` flag, like the JSON Schema's own patterns.
enum RegexDialectChecks {
    static func check(_ manifest: PluginManifest) -> [ManifestIssue] {
        let root = JSONPointer()
        var patterns: [(JSONPointer, String)] = []
        for (index, action) in manifest.actions.enumerated() {
            if let regex = action.when?.regex { patterns.append((root / "actions" / index / "when" / "regex", regex)) }
        }
        for (index, preference) in manifest.preferences.enumerated() {
            if let pattern = preference.pattern { patterns.append((root / "preferences" / index / "pattern", pattern)) }
            if let pattern = preference.itemPattern { patterns.append((root / "preferences" / index / "itemPattern", pattern)) }
        }
        guard !patterns.isEmpty else { return [] }
        let javaScript = JavaScriptRegexCompiler()
        return patterns.compactMap { pointer, pattern in
            if let error = javaScript.error(compiling: pattern) {
                return ManifestIssue(pointer.description, "is not a valid JavaScript regular expression: \(error)")
            }
            if (try? NSRegularExpression(pattern: pattern)) == nil {
                return ManifestIssue(pointer.description, "uses syntax Baron's regular expressions (ICU) don't support")
            }
            return nil
        }
    }
}

/// Compiles patterns with JavaScriptCore's `RegExp`. Not thread-safe; make one per use.
struct JavaScriptRegexCompiler {
    private let context = JSContext()!

    /// The engine's message when the pattern doesn't compile, or nil.
    func error(compiling pattern: String) -> String? {
        context.exception = nil
        let compile = context.evaluateScript("(function (p) { new RegExp(p, 'u'); })")
        compile?.call(withArguments: [pattern])
        defer { context.exception = nil }
        return context.exception.map { $0.toString() ?? "invalid" }
    }
}
