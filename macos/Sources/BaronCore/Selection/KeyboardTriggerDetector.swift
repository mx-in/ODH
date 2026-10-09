/// Recognises keyboard selection gestures and debounces them.
///
/// A run of ⇧-arrow presses is one selection, so the trigger fires only once
/// the keys have been quiet for `quietPeriod`. The caller schedules a check
/// after each gesture and fires only if `isLatest` still holds.
public struct KeyboardTriggerDetector: Sendable {
    public static let quietPeriod: Double = 0.3

    /// macOS virtual key codes.
    enum Key {
        static let a: UInt16 = 0
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let home: UInt16 = 115, end: UInt16 = 119, pageUp: UInt16 = 116, pageDown: UInt16 = 121
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let command = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    private var generation = 0

    public init() {}

    /// ⇧ with an arrow, Home/End or Page keys (⌘ or ⌥ may extend it), or ⌘A.
    public static func isSelectionGesture(keyCode: UInt16, modifiers: Modifiers) -> Bool {
        if keyCode == Key.a { return modifiers == [.command] }
        let movement: Set<UInt16> = [Key.left, Key.right, Key.down, Key.up, Key.home, Key.end, Key.pageUp, Key.pageDown]
        return movement.contains(keyCode) && modifiers.contains(.shift) && !modifiers.contains(.control)
    }

    /// Records a key press. Returns a token when it is a selection gesture; check it with `isLatest` after `quietPeriod`.
    public mutating func handleKey(keyCode: UInt16, modifiers: Modifiers) -> Int? {
        generation += 1
        return Self.isSelectionGesture(keyCode: keyCode, modifiers: modifiers) ? generation : nil
    }

    /// True when no key was pressed after the one that produced `token`.
    public func isLatest(_ token: Int) -> Bool {
        token == generation
    }
}
