import Foundation

/// A permission a plugin declares or is granted. Design: docs/design/plugin-platform/04-permissions-and-security.md
public enum PluginPermission: Hashable, Sendable, CustomStringConvertible {
    case contextSentence, contextParagraph, contextPage, contextWindow
    case clipboardRead, selectionReplace, secrets, codeDynamic
    case network(NetworkPattern)
    /// `network:*`: may ask for any host, one at a time; only valid as an optional permission.
    case anyNetwork

    static let fixed: [String: PluginPermission] = [
        "context.sentence": .contextSentence, "context.paragraph": .contextParagraph, "context.page": .contextPage,
        "context.window": .contextWindow, "clipboard.read": .clipboardRead, "selection.replace": .selectionReplace,
        "secrets": .secrets, "code.dynamic": .codeDynamic,
    ]

    public init?(_ name: String) {
        if let fixed = Self.fixed[name] {
            self = fixed
        } else if name == "network:*" {
            self = .anyNetwork
        } else if name.hasPrefix("network:"), let pattern = NetworkPattern(String(name.dropFirst("network:".count))) {
            self = .network(pattern)
        } else {
            return nil
        }
    }

    public var description: String {
        switch self {
        case .network(let pattern): "network:\(pattern)"
        case .anyNetwork: "network:*"
        default: Self.fixed.first { $0.value == self }!.key
        }
    }
}

/// The part after `network:`: `dict.cn`, `*.youdao.com`, `api.example.com:8443`, `http://example.com`, `127.0.0.1:8765`.
public struct NetworkPattern: Hashable, Sendable, CustomStringConvertible {
    public var scheme: String?
    public var wildcard: Bool
    public var host: String
    public var port: Int?

    public init?(_ text: String) {
        var rest = Substring(text)
        if rest.hasPrefix("https://") { scheme = "https"; rest = rest.dropFirst(8) }
        else if rest.hasPrefix("http://") { scheme = "http"; rest = rest.dropFirst(7) }
        else { scheme = nil }
        wildcard = rest.hasPrefix("*.")
        if wildcard { rest = rest.dropFirst(2) }
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = String(rest[...close]).lowercased()
            rest = rest[rest.index(after: close)...]
        } else {
            let hostPart = rest.prefix { $0 != ":" }
            host = String(hostPart).lowercased()
            rest = rest.dropFirst(hostPart.count)
        }
        if rest.hasPrefix(":") {
            guard let number = Int(rest.dropFirst()), (1...65535).contains(number) else { return nil }
            port = number
        } else if !rest.isEmpty {
            return nil
        } else {
            port = nil
        }
        guard !host.isEmpty, !host.contains("/") else { return nil }
    }

    public var description: String {
        (scheme.map { "\($0)://" } ?? "") + (wildcard ? "*." : "") + host + (port.map { ":\($0)" } ?? "")
    }

    /// Loopback entries may use plain http without writing the scheme out.
    public var isLoopback: Bool { NetworkAddress.isLoopback(host) }

    /// Whether requests to `url` fall under this pattern: https on 443 unless the pattern names a scheme or port;
    /// `*.` covers subdomains only; an IP literal in a private, link-local or loopback range only matches an exact entry.
    public func covers(_ url: URL) -> Bool {
        guard let target = NetworkTarget(url) else { return false }
        return covers(target)
    }

    public func covers(_ target: NetworkTarget) -> Bool {
        let schemeOK = scheme.map { $0 == target.scheme } ?? (target.scheme == "https" || isLoopback)
        let hostOK = wildcard ? target.host.hasSuffix("." + host) : target.host == host
        if wildcard, NetworkAddress.isRestricted(target.host) { return false }
        let wantedPort = port ?? (target.scheme == "https" ? 443 : 80)
        return schemeOK && hostOK && target.port == wantedPort
    }
}

/// A request's origin: scheme, lowercase host (IPv6 in brackets) and port.
public struct NetworkTarget: Hashable, Sendable {
    public var scheme: String
    public var host: String
    public var port: Int

    public init?(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              var host = components.percentEncodedHost?.lowercased(), !host.isEmpty else { return nil }
        if host.contains(":"), !host.hasPrefix("[") { host = "[\(host)]" }
        self.scheme = scheme
        self.host = host
        port = components.port ?? (scheme == "https" ? 443 : 80)
    }

    /// The permission naming exactly this origin, as prompts and `permission_denied` errors show it.
    public var permissionName: String {
        let defaultPort = scheme == "https" ? 443 : 80
        let needsScheme = scheme == "http" && !NetworkAddress.isLoopback(host)
        return "network:" + (needsScheme ? "http://" : "") + host + (port == defaultPort ? "" : ":\(port)")
    }
}

/// Address ranges a public name must never reach.
public enum NetworkAddress {
    public static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "[::1]" || host == "::1" || host.hasPrefix("127.")
    }

    /// Loopback, private (10/8, 172.16/12, 192.168/16, fc00::/7), link-local (169.254/16, fe80::/10) or unspecified.
    public static func isRestricted(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if isLoopback(host) { return true }
        let parts = bare.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, bare.split(separator: ".").count == 4 {
            switch (parts[0], parts[1]) {
            case (10, _), (127, _), (0, _): return true
            case (172, 16...31), (192, 168), (169, 254): return true
            default: return false
            }
        }
        if bare.contains(":") {
            let lower = bare.lowercased()
            return lower == "::" || lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower.hasPrefix("fe8") || lower.hasPrefix("fe9")
                || lower.hasPrefix("fea") || lower.hasPrefix("feb") || lower.hasPrefix("::ffff:127.") || lower.hasPrefix("::ffff:10.")
                || lower.hasPrefix("::ffff:192.168.")
        }
        return false
    }
}
