import Foundation
import Testing
@testable import BaronCore

/// The manifest corpus shared with `@baron/api` (packages/api/test/corpus): plugin folders with
/// manifest.json, expect.json and the files the manifest names.
struct ManifestCorpusCase: CustomTestStringConvertible, Sendable {
    enum Expectation: Equatable, Sendable {
        case valid
        case rejectedBySchema(String)
        case rejectedBySemantics(String)
    }

    let name: String
    let folder: URL
    let expectation: Expectation

    var testDescription: String { name }

    func manifestData() throws -> Data {
        try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
    }

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("packages/api/test/corpus")

    static let all: [ManifestCorpusCase] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.sorted().compactMap { name in
            let folder = root.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("expect.json")),
                  let expect = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let pointer = expect["pointer"] as? String ?? ""
            let expectation: Expectation = switch expect["rejectedBy"] as? String {
            case "schema": .rejectedBySchema(pointer)
            case "semantic": .rejectedBySemantics(pointer)
            default: .valid
            }
            return ManifestCorpusCase(name: name, folder: folder, expectation: expectation)
        }
    }()
}
