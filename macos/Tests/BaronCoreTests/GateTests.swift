import Testing
@testable import BaronCore

struct GateTests {
    private let gate = Gate(excludedApps: ExcludedAppRule.defaults.union(["com.example.game"]))

    @Test func textAreaInANormalAppPasses() {
        #expect(gate.evaluate(GateInput(bundleIdentifier: "com.apple.TextEdit", role: "AXTextArea")) == .pass)
    }

    @Test func unknownRolePasses() {
        #expect(gate.evaluate(GateInput(bundleIdentifier: "com.example.app", role: nil)) == .pass)
    }

    @Test func excludedAppsAreRejected() {
        #expect(gate.evaluate(GateInput(bundleIdentifier: "com.1password.1password", role: "AXTextArea")) == .reject(.excludedApp))
        #expect(gate.evaluate(GateInput(bundleIdentifier: "com.example.game", role: "AXTextArea")) == .reject(.excludedApp))
        #expect(gate.evaluate(GateInput(bundleIdentifier: Baron.bundleIdentifier, role: "AXTextArea")) == .reject(.excludedApp))
    }

    @Test func passwordFieldsAreRejected() {
        let input = GateInput(bundleIdentifier: "com.apple.Safari", role: "AXTextField", subrole: "AXSecureTextField")
        #expect(gate.evaluate(input) == .reject(.secureInput))
    }

    @Test func secureKeyboardInputIsRejected() {
        let input = GateInput(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", secureInputEnabled: true)
        #expect(gate.evaluate(input) == .reject(.secureInput))
    }

    @Test(arguments: ["AXButton", "AXMenuItem", "AXScrollBar", "AXImage"])
    func controlsAreRejected(role: String) {
        #expect(gate.evaluate(GateInput(bundleIdentifier: "com.example.app", role: role)) == .reject(.nonTextRole))
    }

    @Test func windowDragsAreRejected() {
        let input = GateInput(bundleIdentifier: "com.apple.TextEdit", role: "AXTextArea", windowDragged: true)
        #expect(gate.evaluate(input) == .reject(.windowDrag))
    }

    @Test func firstVetoWins() {
        let input = GateInput(bundleIdentifier: "com.bitwarden.desktop", role: "AXButton", windowDragged: true)
        #expect(gate.evaluate(input) == .reject(.excludedApp))
    }
}
