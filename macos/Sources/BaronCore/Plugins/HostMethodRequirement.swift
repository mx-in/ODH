/// What a host method needs before it runs. Design: 03-host-api-and-ipc.md#namespace-rules
public struct HostMethodRequirement: Equatable, Sendable {
    /// A permission from the catalogue, or nil.
    public var permission: PluginPermission?
    /// A click on the plugin's button or panel within the last few seconds.
    public var needsUserAction: Bool
    /// Network permissions are checked per URL, including redirects, by the HTTP service itself.
    public var checksNetwork: Bool

    public init(permission: PluginPermission? = nil, needsUserAction: Bool = false, checksNetwork: Bool = false) {
        self.permission = permission
        self.needsUserAction = needsUserAction
        self.checksNetwork = checksNetwork
    }

    static let free = HostMethodRequirement()
    static let userAction = HostMethodRequirement(needsUserAction: true)

    /// Nil for a method the host doesn't have.
    public static func of(namespace: String, method: String) -> HostMethodRequirement? {
        table["\(namespace).\(method)"]
    }

    static let table: [String: HostMethodRequirement] = [
        "log.debug": free, "log.info": free, "log.warn": free, "log.error": free,
        "http.fetch": HostMethodRequirement(checksNetwork: true),
        "http.cancel": free,
        "clipboard.readText": HostMethodRequirement(permission: .clipboardRead, needsUserAction: true),
        "clipboard.writeText": userAction,
        "selection.replace": HostMethodRequirement(permission: .selectionReplace, needsUserAction: true),
        "storage.get": free, "storage.set": free, "storage.remove": free, "storage.keys": free, "storage.usage": free,
        "cache.get": free, "cache.set": free, "cache.remove": free, "cache.clear": free,
        "secrets.get": HostMethodRequirement(permission: .secrets), "secrets.set": HostMethodRequirement(permission: .secrets),
        "secrets.remove": HostMethodRequirement(permission: .secrets),
        "text.segment": free,
        "ui.toast": free, "ui.openSettings": free,
        "ui.openUrl": userAction, "ui.openWebView": userAction, "ui.show": userAction,
        "ui.postMessage": free, "ui.closeView": free,
        "permissions.query": free,
        "permissions.request": userAction,
    ]

    /// Every method the host offers, for contract tests.
    public static var allMethods: [String] { table.keys.sorted() }
}
