import Testing
@testable import BaronCore

@Test func bundleIdentifierIsStable() {
    #expect(Baron.bundleIdentifier == "org.odh.baron")
}
