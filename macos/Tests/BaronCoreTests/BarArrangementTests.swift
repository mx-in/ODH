import Foundation
import Testing
@testable import BaronCore

struct BarArrangementTests {
    let items = ["copy", "search", "plugin:a/lookup", "plugin:b/upper"].map { BarItem(id: $0, title: $0, symbolName: nil) }

    @Test func keepsTheUsualOrderWithoutPreferences() {
        #expect(BarArrangement().arrange(items).map(\.id) == ["copy", "search", "plugin:a/lookup", "plugin:b/upper"])
    }

    @Test func followsTheUsersOrderWithNewActionsAtTheEnd() {
        let arrangement = BarArrangement(order: ["plugin:a/lookup", "copy"])
        #expect(arrangement.arrange(items).map(\.id) == ["plugin:a/lookup", "copy", "search", "plugin:b/upper"])
    }

    @Test func hidesActions() {
        #expect(BarArrangement(hidden: ["search"]).arrange(items).map(\.id) == ["copy", "plugin:a/lookup", "plugin:b/upper"])
    }

    @Test func movesAnAction() {
        var arrangement = BarArrangement()
        arrangement.move("plugin:a/lookup", by: -2, among: items.map(\.id))
        #expect(arrangement.arrange(items).map(\.id).first == "plugin:a/lookup")
        arrangement.move("plugin:a/lookup", by: 10, among: items.map(\.id))
        #expect(arrangement.arrange(items).map(\.id).last == "plugin:a/lookup")
    }

    @Test func runsOnSelectionOnlyWhenAllowedAndInTheChosenApps() {
        let arrangement = BarArrangement(runOnSelection: ["plugin:a/lookup": [], "plugin:b/upper": ["com.apple.Safari"]])
        #expect(arrangement.automaticAction(among: items, allowed: ["plugin:a/lookup"], app: "com.apple.Notes") == "plugin:a/lookup")
        #expect(arrangement.automaticAction(among: items, allowed: [], app: "com.apple.Notes") == nil)
        let onlySafari = BarArrangement(runOnSelection: ["plugin:b/upper": ["com.apple.Safari"]])
        #expect(onlySafari.automaticAction(among: items, allowed: ["plugin:b/upper"], app: "com.apple.Safari") == "plugin:b/upper")
        #expect(onlySafari.automaticAction(among: items, allowed: ["plugin:b/upper"], app: "com.apple.Notes") == nil)
    }

    @Test func oldSettingsStillLoad() throws {
        let settings = try JSONDecoder().decode(BaronSettings.self, from: Data(#"{"isPaused": false}"#.utf8))
        #expect(settings.bar == BarArrangement())
    }
}
