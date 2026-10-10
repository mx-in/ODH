import Foundation
import Testing
@testable import BaronCore

struct NetworkCorpusCase: Decodable, Sendable, CustomTestStringConvertible {
    var permission: String
    var url: String
    var covers: Bool
    var note: String
    var testDescription: String { "\(permission) vs \(url)" }

    static let all: [NetworkCorpusCase] = {
        let file = ManifestCorpusCase.root.deletingLastPathComponent().appendingPathComponent("network-corpus.json")
        return (try? JSONDecoder().decode([NetworkCorpusCase].self, from: Data(contentsOf: file))) ?? []
    }()
}

struct PluginPermissionTests {
    @Test func parsesEveryKindOfName() {
        for name in ["context.sentence", "clipboard.read", "selection.replace", "secrets", "code.dynamic", "network:*", "network:dict.cn",
                     "network:*.youdao.com", "network:api.example.com:8443", "network:http://example.com", "network:127.0.0.1:8765", "network:[::1]:8765"] {
            #expect(PluginPermission(name)?.description == name)
        }
        for bad in ["context.selection", "network:", "network:dict.cn:0", "network:dict.cn/path", "network:dict.cn:x"] {
            #expect(PluginPermission(bad) == nil)
        }
    }

    @Test func theCorpusIsThere() {
        #expect(NetworkCorpusCase.all.count >= 20)
    }

    @Test(arguments: NetworkCorpusCase.all)
    func matchesTheSharedCorpus(_ c: NetworkCorpusCase) {
        let covered: Bool
        if case .network(let pattern)? = PluginPermission(c.permission) { covered = pattern.covers(URL(string: c.url)!) } else { covered = false }
        #expect(covered == c.covers, "\(c.note)")
    }

    @Test func namesThePermissionForATarget() {
        #expect(NetworkTarget(URL(string: "https://Dict.cn/fox")!)?.permissionName == "network:dict.cn")
        #expect(NetworkTarget(URL(string: "http://example.com/")!)?.permissionName == "network:http://example.com")
        #expect(NetworkTarget(URL(string: "http://127.0.0.1:8765/")!)?.permissionName == "network:127.0.0.1:8765")
        #expect(NetworkTarget(URL(string: "https://[::1]:8443/")!)?.permissionName == "network:[::1]:8443")
    }

    @Test func knowsRestrictedAddresses() {
        for host in ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.0.1", "169.254.1.1", "0.0.0.0", "[::1]", "[fe80::1]", "[fd00::1]", "localhost"] {
            #expect(NetworkAddress.isRestricted(host), "\(host)")
        }
        for host in ["8.8.8.8", "172.32.0.1", "dict.cn", "[2001:db8::1]"] {
            #expect(!NetworkAddress.isRestricted(host), "\(host)")
        }
    }

    @Test func wildcardsNeverCoverRestrictedAddresses() {
        let pattern = NetworkPattern("*.0.1")!
        #expect(!pattern.covers(URL(string: "https://10.0.0.1/")!))
    }
}
