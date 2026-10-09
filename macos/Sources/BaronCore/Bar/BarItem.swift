/// One button on the action bar.
public struct BarItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// An SF Symbols name for the macOS host. Plugin icons will be SVG instead.
    public var symbolName: String?

    public init(id: String, title: String, symbolName: String? = nil) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
    }
}
