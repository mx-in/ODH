import Testing
@testable import BaronCore

struct NativeTextContextTests {
    private func range(of word: String, in text: String) -> Range<Int> {
        let r = text.range(of: word)!
        return r.lowerBound.utf16Offset(in: text)..<r.upperBound.utf16Offset(in: text)
    }

    @Test func paragraphStopsAtLineBreaks() {
        let window = "First paragraph.\nThe quick brown fox jumps. It runs away.\nLast one."
        let span = NativeTextContext.paragraph(in: window, selection: range(of: "fox", in: window), windowStartsAtDocumentStart: true, windowEndsAtDocumentEnd: true)!
        #expect(span.text == "The quick brown fox jumps. It runs away.")
        #expect(span.truncated == false)
        let selected = Array(span.text.utf16)[span.selectionStart..<span.selectionEnd]
        #expect(String(decoding: selected, as: UTF16.self) == "fox")
    }

    @Test func paragraphReachingAWindowEdgeIsTruncated() {
        let window = "brown fox jumps over"
        let span = NativeTextContext.paragraph(in: window, selection: range(of: "fox", in: window), windowStartsAtDocumentStart: false, windowEndsAtDocumentEnd: true)!
        #expect(span.text == window)
        #expect(span.truncated)
    }

    @Test func sentenceHoldsTheSelection() {
        let text = "The quick brown fox jumps. It runs away fast."
        let paragraph = TextSpan(text: text, selectionStart: range(of: "runs", in: text).lowerBound, selectionEnd: range(of: "runs", in: text).upperBound)
        let sentence = NativeTextContext.sentence(in: paragraph)!
        #expect(sentence.text == "It runs away fast.")
        #expect(sentence.selectionStart == 3)
        #expect(sentence.selectionEnd == 7)
    }

    @Test func selectionAcrossSentencesJoinsThem() {
        let text = "One two. Three four. Five six."
        let selection = range(of: "two. Three", in: text)
        let paragraph = TextSpan(text: text, selectionStart: selection.lowerBound, selectionEnd: selection.upperBound)
        #expect(NativeTextContext.sentence(in: paragraph)?.text == "One two. Three four.")
    }

    @Test func chineseSentencesSplitOnFullWidthPunctuation() {
        let text = "今天天气很好。我们去公园散步吧！"
        let selection = range(of: "公园", in: text)
        let paragraph = TextSpan(text: text, selectionStart: selection.lowerBound, selectionEnd: selection.upperBound)
        #expect(NativeTextContext.sentence(in: paragraph)?.text == "我们去公园散步吧！")
    }

    @Test func offsetsAreUTF16() {
        let text = "Emoji 😀 then word here."
        let selection = range(of: "word", in: text)
        let paragraph = NativeTextContext.paragraph(in: text, selection: selection, windowStartsAtDocumentStart: true, windowEndsAtDocumentEnd: true)!
        #expect(paragraph.selectionStart == 14) // 😀 is two UTF-16 units
    }

    @Test func longParagraphIsCappedAroundTheSelection() {
        let filler = String(repeating: "a", count: 3_000)
        let window = filler + " TARGET " + filler
        let span = NativeTextContext.paragraph(in: window, selection: range(of: "TARGET", in: window), windowStartsAtDocumentStart: true, windowEndsAtDocumentEnd: true)!
        #expect(span.text.utf16.count == NativeTextContext.paragraphCap)
        #expect(span.truncated)
        let selected = Array(span.text.utf16)[span.selectionStart..<span.selectionEnd]
        #expect(String(decoding: selected, as: UTF16.self) == "TARGET")
    }
}

struct CappedSpanTests {
    @Test func shortSpanIsUnchanged() {
        let span = TextSpan(text: "short", selectionStart: 1, selectionEnd: 3)
        #expect(NativeTextContext.capped(span, to: 10) == span)
    }

    @Test func longSpanKeepsTheSelection() {
        let text = String(repeating: "x", count: 50) + "SEL" + String(repeating: "y", count: 50)
        let span = TextSpan(text: text, selectionStart: 50, selectionEnd: 53)
        let capped = NativeTextContext.capped(span, to: 13)
        #expect(capped.text == "xxxxxSELyyyyy")
        #expect(capped.selectionStart == 5)
        #expect(capped.truncated)
    }
}
