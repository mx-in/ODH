import Foundation
import Testing
@testable import BaronCore

@MainActor
struct PluginActionCatalogTests {
    let catalog = PluginActionCatalog(entries: [
        .init(pluginID: "org.odh.dictionary", pluginName: "ODH", actionID: "lookup", title: "Look up", when: WhenRules(maxLength: 64, contentTypes: [.word])),
        .init(pluginID: "org.example.upper", pluginName: "Upper", actionID: "upper", title: "UPPER", when: WhenRules(editable: true)),
        .init(pluginID: "org.example.any", pluginName: "Any", actionID: "any", title: "Any", when: nil),
    ])

    @Test func offersActionsWhoseRulesMatch() {
        #expect(catalog.items(for: WhenInput(text: "fox", bundleIdentifier: nil, editable: false)).map(\.title) == ["Look up", "Any"])
        #expect(catalog.items(for: WhenInput(text: "two words", bundleIdentifier: nil, editable: true)).map(\.title) == ["UPPER", "Any"])
    }

    @Test func itemIDsLeadBackToTheirEntry() {
        let item = catalog.items(for: WhenInput(text: "fox", bundleIdentifier: nil, editable: false))[0]
        #expect(item.id == "plugin:org.odh.dictionary/lookup")
        #expect(catalog.entry(forItemID: item.id)?.pluginName == "ODH")
        #expect(catalog.entry(forItemID: "builtin.copy") == nil)
    }

    @Test func resolvesTitlesFromManifests() throws {
        let odh = ManifestCorpusCase.root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("plugins/odh")
        let manifest = try #require(ManifestValidator().validate(package: odh).manifest)
        let chinese = PluginActionCatalog([(manifest, PluginLocalizer(package: odh, defaultLocale: "en", preferredLanguages: ["zh-Hans-CN"]))])
        #expect(chinese.entries.map(\.title) == ["查词"])
        #expect(chinese.entries.first?.pluginName == "在线词典助手")
    }

    @Test func thePipelineShowsPluginActionsAfterBuiltIns() async {
        var pipeline = SelectionPipeline(gate: Gate(rules: []))
        pipeline.plugins = catalog
        let source = FakeSource(text: "fox")
        guard case .show(let run) = await pipeline.run(Trigger(kind: .doubleClick, location: .zero, windowDragged: false), source: source) else {
            Issue.record("not shown"); return
        }
        #expect(run.items.map(\.id).suffix(2) == ["plugin:org.odh.dictionary/lookup", "plugin:org.example.any/any"])
        #expect(run.items.first?.id.hasPrefix("builtin.") == true)
        #expect(run.editable == false && run.app.bundleIdentifier == "com.apple.TextEdit")
    }
}
