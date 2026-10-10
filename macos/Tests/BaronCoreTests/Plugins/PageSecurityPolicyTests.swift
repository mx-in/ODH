import Testing
@testable import BaronCore

struct PageSecurityPolicyTests {
    func directive(_ name: String, in header: String) -> String? {
        header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix(name + " ") }
    }

    @Test func allowsOnlyThePackageWithoutPermissions() {
        let header = PageSecurityPolicy.header(granted: ["context.sentence"])
        #expect(header.hasPrefix("default-src 'none'"))
        #expect(directive("script-src", in: header) == "script-src 'self'")
        #expect(directive("img-src", in: header) == "img-src 'self' data: blob:")
        #expect(directive("connect-src", in: header) == "connect-src 'none'")
        for closed in ["frame-src 'none'", "form-action 'none'", "base-uri 'none'"] { #expect(header.contains(closed)) }
    }

    @Test func letsImagesAndMediaComeFromFetchableHosts() {
        let header = PageSecurityPolicy.header(granted: ["network:dict.cn", "network:*.youdao.com", "network:api.example.com:8443",
                                                         "network:http://plain.example.com", "network:127.0.0.1:8765"])
        let hosts = "https://dict.cn https://*.youdao.com https://api.example.com:8443 http://plain.example.com http://127.0.0.1:8765 https://127.0.0.1:8765"
        #expect(directive("img-src", in: header) == "img-src 'self' data: blob: " + hosts)
        #expect(directive("media-src", in: header) == "media-src 'self' blob: " + hosts)
        // Fetching from the page still goes through baron.http.fetch.
        #expect(directive("connect-src", in: header) == "connect-src 'none'")
    }

    @Test func allowsEvalOnlyWithDynamicCode() {
        #expect(directive("script-src", in: PageSecurityPolicy.header(granted: ["code.dynamic"])) == "script-src 'self' 'unsafe-eval' blob:")
    }
}
