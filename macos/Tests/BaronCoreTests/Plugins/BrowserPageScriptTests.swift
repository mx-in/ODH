import Testing
@testable import BaronCore

struct BrowserPageScriptTests {
    @Test func asksSafariAndTheChromeFamilyOnly() {
        #expect(BrowserPageScript.source(for: "com.apple.Safari")?.contains("front document") == true)
        #expect(BrowserPageScript.source(for: "com.google.Chrome")?.contains("active tab of front window") == true)
        #expect(BrowserPageScript.source(for: "company.thebrowser.Browser") != nil)
        #expect(BrowserPageScript.source(for: "com.apple.TextEdit") == nil)
    }

    @Test func readsTheAddressAndTitle() {
        #expect(BrowserPageScript.page(fromOutput: "https://example.com/a?b=1\nExample, with a comma\n") == .init(url: "https://example.com/a?b=1", title: "Example, with a comma"))
        #expect(BrowserPageScript.page(fromOutput: "https://example.com/\n\n") == .init(url: "https://example.com/", title: nil))
        // An empty tab, an error message or a browser-internal page isn't a page address.
        #expect(BrowserPageScript.page(fromOutput: "") == nil)
        #expect(BrowserPageScript.page(fromOutput: "missing value\n") == nil)
        #expect(BrowserPageScript.page(fromOutput: "chrome://newtab/\nNew Tab") == nil)
    }
}
