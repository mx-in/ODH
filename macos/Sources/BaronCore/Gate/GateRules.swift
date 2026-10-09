/// Rejects apps the user (or the defaults) excluded.
public struct ExcludedAppRule: GateRule {
    /// Password managers, remote desktops, and Baron itself.
    public static let defaults: Set<String> = [
        Baron.bundleIdentifier,
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.microsoft.rdc.macos",
        "com.realvnc.vncviewer",
        "com.teamviewer.TeamViewer",
    ]

    public var excluded: Set<String>

    public init(excluded: Set<String>) {
        self.excluded = excluded
    }

    public func reject(_ input: GateInput) -> GateReason? {
        guard let id = input.bundleIdentifier, excluded.contains(id) else { return nil }
        return .excludedApp
    }
}

/// Rejects password fields, and anything typed while macOS secure input is on.
public struct SecureInputRule: GateRule {
    public static let secureSubrole = "AXSecureTextField"

    public init() {}

    public func reject(_ input: GateInput) -> GateReason? {
        if input.secureInputEnabled { return .secureInput }
        if input.subrole == Self.secureSubrole || input.role == Self.secureSubrole { return .secureInput }
        return nil
    }
}

/// Rejects controls that can't hold a text selection. An unknown role passes.
public struct TextRoleRule: GateRule {
    public static let nonTextRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXMenu", "AXMenuBar", "AXMenuBarItem", "AXMenuItem",
        "AXScrollBar", "AXSlider", "AXIncrementor", "AXSplitter",
        "AXImage", "AXToolbar", "AXDockItem", "AXDisclosureTriangle",
    ]

    public init() {}

    public func reject(_ input: GateInput) -> GateReason? {
        guard let role = input.role, Self.nonTextRoles.contains(role) else { return nil }
        return .nonTextRole
    }
}

/// Rejects a drag that moved or resized the window: the user was moving it, not selecting.
public struct WindowDragRule: GateRule {
    public init() {}

    public func reject(_ input: GateInput) -> GateReason? {
        input.windowDragged ? .windowDrag : nil
    }
}
