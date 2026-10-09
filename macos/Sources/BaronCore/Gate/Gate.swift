/// What the gate knows about a possible selection before reading any text.
public struct GateInput: Sendable {
    public var bundleIdentifier: String?
    public var role: String?
    public var subrole: String?
    public var secureInputEnabled: Bool
    public var windowDragged: Bool

    public init(bundleIdentifier: String?, role: String?, subrole: String? = nil, secureInputEnabled: Bool = false, windowDragged: Bool = false) {
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.secureInputEnabled = secureInputEnabled
        self.windowDragged = windowDragged
    }
}

public enum GateReason: String, Sendable {
    case excludedApp
    case secureInput
    case nonTextRole
    case windowDrag
}

public enum GateDecision: Equatable, Sendable {
    case pass
    case reject(GateReason)
}

/// One cheap check that can veto reading the selection.
public protocol GateRule: Sendable {
    func reject(_ input: GateInput) -> GateReason?
}

/// Runs the rules in order; the first veto wins.
public struct Gate: Sendable {
    public var rules: [any GateRule]

    public init(rules: [any GateRule]) {
        self.rules = rules
    }

    /// The standard rule set, with the user's excluded apps.
    public init(excludedApps: Set<String>) {
        self.init(rules: [
            ExcludedAppRule(excluded: excludedApps),
            SecureInputRule(),
            TextRoleRule(),
            WindowDragRule(),
        ])
    }

    public func evaluate(_ input: GateInput) -> GateDecision {
        for rule in rules {
            if let reason = rule.reject(input) { return .reject(reason) }
        }
        return .pass
    }
}
