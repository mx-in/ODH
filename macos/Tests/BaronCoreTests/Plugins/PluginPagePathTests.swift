import Foundation
import Testing
@testable import BaronCore

struct PluginPagePathTests {
    let package: URL = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("baron-pages-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("views"), withIntermediateDirectories: true)
        try! Data("<p>hi</p>".utf8).write(to: root.appendingPathComponent("views/popup.html"))
        try! Data("secret".utf8).write(to: root.deletingLastPathComponent().appendingPathComponent("outside-\(root.lastPathComponent).txt"))
        try! FileManager.default.createSymbolicLink(at: root.appendingPathComponent("views/escape.html"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        return root
    }()

    @Test func findsFilesInThePackage() {
        #expect(PluginPagePath.resolve("views/popup.html", in: package)?.lastPathComponent == "popup.html")
        #expect(PluginPagePath.resolve("./views/popup.html", in: package) != nil)
    }

    @Test func refusesPathsOutOfThePackage() {
        for path in ["", "/etc/hosts", "../outside-\(package.lastPathComponent).txt", "views/../../x", "https://example.com/a.html",
                     "views", "views/missing.html", "views/escape.html", "views\\popup.html"] {
            #expect(PluginPagePath.resolve(path, in: package) == nil, "\(path)")
        }
    }

    @Test func servesKnownTypes() {
        #expect(PluginPagePath.mimeType(for: URL(fileURLWithPath: "/a/popup.HTML")) == "text/html; charset=utf-8")
        #expect(PluginPagePath.mimeType(for: URL(fileURLWithPath: "/a/say.mp3")) == "audio/mpeg")
        #expect(PluginPagePath.mimeType(for: URL(fileURLWithPath: "/a/blob")) == "application/octet-stream")
    }
}
