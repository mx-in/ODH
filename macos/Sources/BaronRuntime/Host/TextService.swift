import Foundation
import BaronCore
import NaturalLanguage

/// `host.text.segment`: word or sentence boundaries from the system's tokenizer, as UTF-16 offsets
/// (JavaScript string indices). Words need a letter or digit, so spaces, punctuation and emoji aren't words
/// (as with Intl.Segmenter's isWordLike); sentences cover the text, trailing spaces included.
public struct TextService: HostService {
    public let namespace = "text"

    public init() {}

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        guard method == "segment" else { throw arguments.unknownMethod() }
        let text = try arguments.string(0)
        let unit: NLTokenUnit
        switch try arguments.string(1) {
        case "word": unit = .word
        case "sentence": unit = .sentence
        default: throw arguments.invalid(1, "word or sentence")
        }
        return .array(Self.segments(of: text, unit: unit).map { .object(["start": .number(Double($0.start)), "end": .number(Double($0.end))]) })
    }

    static func segments(of text: String, unit: NLTokenUnit) -> [(start: Int, end: Int)] {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .filter { unit != .word || text[$0].unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) } }
            .map { range in
            (text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound.samePosition(in: text.utf16) ?? text.utf16.startIndex),
             text.utf16.distance(from: text.utf16.startIndex, to: range.upperBound.samePosition(in: text.utf16) ?? text.utf16.endIndex))
        }
    }
}
