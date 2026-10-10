/// The Content Security Policy every plugin page is served with. Images and audio may load from the hosts the
/// plugin may `fetch` from; scripts only from its package; data requests only through `baron.http.fetch`.
/// Design: docs/design/plugin-platform/07-web-views.md#security-policy
public enum PageSecurityPolicy {
    /// - Parameter granted: the plugin's permissions: its manifest's, plus run-time network grants it holds.
    public static func header(granted: [String]) -> String {
        let permissions = granted.compactMap(PluginPermission.init)
        let hosts = permissions.flatMap { permission -> [String] in
            guard case .network(let pattern) = permission else { return [] }
            return sources(for: pattern)
        }
        let dynamic = permissions.contains(.codeDynamic)
        let remote = hosts.isEmpty ? "" : " " + hosts.joined(separator: " ")
        return [
            "default-src 'none'",
            "script-src 'self'" + (dynamic ? " 'unsafe-eval' blob:" : ""),
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob:" + remote,
            "media-src 'self' blob:" + remote,
            "font-src 'self' data:",
            "connect-src 'none'",
            "frame-src 'none'",
            "form-action 'none'",
            "base-uri 'none'",
        ].joined(separator: "; ")
    }

    /// CSP sources covering what the pattern covers for `fetch`: https unless the pattern names a scheme, and
    /// plain http as well for loopback entries.
    static func sources(for pattern: NetworkPattern) -> [String] {
        let host = (pattern.wildcard ? "*." : "") + pattern.host + (pattern.port.map { ":\($0)" } ?? "")
        let schemes = pattern.scheme.map { [$0] } ?? (pattern.isLoopback ? ["http", "https"] : ["https"])
        return schemes.map { "\($0)://\(host)" }
    }
}
