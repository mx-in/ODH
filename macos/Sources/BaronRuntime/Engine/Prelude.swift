import Foundation

/// The prelude from `packages/runtime`, built into this target's resources.
public enum Prelude {
    public static let source: String = {
        guard let url = Bundle.module.url(forResource: "prelude", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("prelude.js is missing from BaronRuntime's resources; run npm run build -w packages/runtime")
        }
        return text
    }()
}
