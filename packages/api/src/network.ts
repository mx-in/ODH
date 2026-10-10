/**
 * Whether a `network:` permission covers a URL's origin, as 04-permissions-and-security.md#network-patterns
 * describes: https on 443 unless the pattern names a scheme or port; loopback may use http; `*.` matches
 * subdomains only. Baron's own matcher (task-006) adds address resolution; this one serves tooling and tests.
 */
export function networkPermissionCovers(permission: string, url: string): boolean {
    const target = url.match(/^(https?):\/\/(\[[^\]]+\]|[^/:?#]+)(?::(\d+))?/i);
    const pattern = permission.match(/^network:(?:(https?):\/\/)?(\*\.)?(\[[^\]]+\]|[^:]+)(?::(\d+))?$/);
    if (!target || !pattern) return false;
    const scheme = target[1]!.toLowerCase();
    const host = target[2]!.toLowerCase();
    const port = target[3] ?? (scheme === "https" ? "443" : "80");
    const [, wantScheme, wildcard, wantHost, wantPort] = pattern;
    const loopback = /^(127\.\d+\.\d+\.\d+|localhost|\[::1\])$/.test(wantHost!);
    const schemeOK = wantScheme ? wantScheme === scheme : scheme === "https" || loopback;
    const hostOK = wildcard ? host.endsWith(`.${wantHost}`) : host === wantHost;
    const portOK = port === (wantPort ?? (scheme === "https" ? "443" : "80"));
    return schemeOK && hostOK && portOK;
}

/** The `network:` permission that names exactly this URL's host, for prompts and `permissions.used`. */
export function networkPermissionFor(url: string): string {
    const target = url.match(/^(https?):\/\/(\[[^\]]+\]|[^/:?#]+)(?::(\d+))?/i);
    if (!target) return "network:?";
    const scheme = target[1]!.toLowerCase();
    const host = target[2]!.toLowerCase();
    const prefix = scheme === "http" && !/^(127\.|localhost|\[::1\])/.test(host) ? "http://" : "";
    return `network:${prefix}${host}${target[3] ? `:${target[3]}` : ""}`;
}
