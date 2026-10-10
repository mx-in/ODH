import Foundation
import Testing
@testable import BaronCore

struct PluginActionResultTests {
    func parse(_ json: String, editable: Bool = true, mayReplace: Bool = true) throws -> Result<PluginActionResult, PluginActionResultError> {
        PluginActionResult.parse(try JSONValue(data: Data(json.utf8)), editable: editable, mayReplace: mayReplace)
    }

    @Test func readsEachResult() throws {
        #expect(try parse("null") == .success(.nothing))
        #expect(try parse(#"{"type": "copy", "text": "FOX"}"#) == .success(.copy("FOX")))
        #expect(try parse(#"{"type": "replace", "text": "FOX"}"#) == .success(.replace("FOX")))
        #expect(try parse(#"{"type": "toast", "message": "hi"}"#) == .success(.toast("hi", kind: "info")))
        #expect(try parse(#"{"type": "toast", "message": "no", "kind": "error"}"#) == .success(.toast("no", kind: "error")))
        #expect(try parse(#"{"type": "openUrl", "url": "https://example.com/a"}"#) == .success(.openURL(URL(string: "https://example.com/a")!)))
    }

    @Test func refusesReplaceWithoutPermissionOrAnEditableSelection() throws {
        #expect(try parse(#"{"type": "replace", "text": "X"}"#, mayReplace: false) == .failure(.init("The plugin can't replace text: it doesn't have the selection.replace permission")))
        #expect(try parse(#"{"type": "replace", "text": "X"}"#, editable: false) == .failure(.init("This selection can't be replaced")))
    }

    @Test func refusesMalformedResults() throws {
        for json in [#""text""#, #"{"type": "copy"}"#, #"{"type": "speak", "text": "x"}"#, #"{"type": "openUrl", "url": "file:///etc/passwd"}"#, #"{"type": "toast", "message": "x", "kind": "loud"}"#] {
            guard case .failure = try parse(json) else { Issue.record("accepted \(json)"); continue }
        }
    }
}
