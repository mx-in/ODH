/**
 * Serves a plugin's host calls in memory, checking permissions as Baron does, and records what the plugin did.
 */
import { bytesToBase64, networkPermissionCovers, networkPermissionFor, type CallEnvelope, type EnvelopeError, type PluginManifest, type ResultEnvelope } from "@baron/api";

export interface MockResponse {
    status?: number;
    headers?: Record<string, string>;
    body?: string | Uint8Array;
}

export type MockRoute = MockResponse | ((request: { url: string; method: string; headers: Record<string, string>; body?: Uint8Array }) => MockResponse | Promise<MockResponse>);

class Refusal extends Error {
    constructor(readonly code: EnvelopeError["code"], message: string, readonly data?: Record<string, unknown>) {
        super(message);
    }
}

export class MockHost {
    readonly storage = new Map<string, unknown>();
    readonly cache = new Map<string, string>();
    readonly secrets = new Map<string, string>();
    readonly toasts: Array<{ message: string; kind: string }> = [];
    readonly openedURLs: string[] = [];
    /** Pages the plugin opened with `host.ui.openWebView`, with the messages it sent each one. */
    readonly views: Array<{ id: string; path: string; data: unknown; messages: unknown[]; open: boolean }> = [];
    readonly replacements: string[] = [];
    readonly logs: Array<{ level: string; text: string }> = [];
    clipboard = "";
    /** Optional permissions the user has allowed. */
    readonly granted = new Set<string>();
    /** Permissions the user denied when asked; not asked again. */
    readonly denied = new Set<string>();
    /** What the user answers when the plugin asks for a permission. */
    promptAnswer: "deny" | "allowOnce" | "alwaysAllow" = "deny";
    /** Whether the user clicked the plugin recently (Baron records a click when it runs an action). */
    userAction = true;
    /** The questions the plugin asked. */
    readonly prompts: string[] = [];
    private readonly routes: Array<{ match: string | RegExp; route: MockRoute }> = [];
    private readonly usedPermissions = new Set<string>();

    constructor(readonly manifest: Pick<PluginManifest, "permissions" | "optionalPermissions">) {}

    readonly http = {
        /** Answers requests whose URL equals `match` (or matches the RegExp). Later mocks win. */
        mock: (match: string | RegExp, route: MockRoute) => void this.routes.unshift({ match, route }),
    };

    /** The permissions the plugin actually used, sorted. */
    get permissionsUsed(): string[] {
        return [...this.usedPermissions].sort();
    }

    private holds(name: string): boolean {
        return (this.manifest.permissions ?? []).includes(name as never) || this.granted.has(name);
    }


    async handle(call: CallEnvelope): Promise<ResultEnvelope> {
        try {
            this.check(call.ns, call.method);
            return { v: 1, kind: "result", id: call.id, ok: true, value: await this.serve(call.ns, call.method, call.args) };
        } catch (error) {
            const refusal = error instanceof Refusal ? error : new Refusal("internal", String(error));
            return { v: 1, kind: "result", id: call.id, ok: false, error: { code: refusal.code, message: refusal.message, ...(refusal.data ? { data: refusal.data } : {}) } };
        }
    }

    /** Baron's PermissionGate: the method's permission, then a recent click where needed. */
    private check(ns: string, method: string): void {
        const requirement = requirements[`${ns}.${method}`];
        if (!requirement) return;
        const [permission, needsClick] = requirement;
        if (permission && !this.holds(permission)) {
            throw new Refusal("permission_denied", `${permission} isn't granted`, { permission, requestable: this.mayRequest(permission) && !this.denied.has(permission) });
        }
        if (needsClick && !this.userAction) throw new Refusal("user_action_required", `host.${ns}.${method} needs a click on the plugin`);
    }

    private mayRequest(name: string): boolean {
        return (this.manifest.optionalPermissions ?? []).includes(name as never) || (name !== "network:*" && this.optionalNetwork(name));
    }

    private openView(id: string) {
        const view = this.views.find((v) => v.id === id && v.open);
        if (!view) throw new Refusal("not_found", `No open view ${id}`);
        return view;
    }

    private state(name: string): "granted" | "prompt" | "denied" {
        if (this.holds(name) || (name.startsWith("network:") && !name.includes("*") && [...(this.manifest.permissions ?? []), ...this.granted].some((p) => networkPermissionCovers(p, `${name.includes("://") ? name.slice(8) : `https://${name.slice(8)}`}/`)))) return "granted";
        return this.mayRequest(name) && !this.denied.has(name) && name !== "network:*" ? "prompt" : "denied";
    }

    private async serve(ns: string, method: string, args: unknown[]): Promise<unknown> {
        const key = String(args[0]);
        switch (`${ns}.${method}`) {
            case "log.debug": case "log.info": case "log.warn": case "log.error":
                this.logs.push({ level: method, text: String(args[0]) });
                return null;
            case "http.fetch": return this.fetch(String(args[0]), (args[1] ?? {}) as Record<string, unknown>);
            case "http.cancel": return null;
            case "storage.get": return this.storage.has(key) ? structuredClone(this.storage.get(key)) : null;
            case "storage.set": this.storage.set(key, structuredClone(args[1])); return null;
            case "storage.remove": this.storage.delete(key); return null;
            case "storage.keys": return [...this.storage.keys()];
            case "storage.usage": return [...this.storage].reduce((n, [k, v]) => n + k.length + JSON.stringify(v).length, 0);
            case "cache.get": return this.cache.get(key) ?? null;
            case "cache.set": this.cache.set(key, String(args[1])); return null;
            case "cache.remove": this.cache.delete(key); return null;
            case "cache.clear": this.cache.clear(); return null;
            case "secrets.get": return this.secrets.get(key) ?? null;
            case "secrets.set": this.secrets.set(key, String(args[1])); return null;
            case "secrets.remove": this.secrets.delete(key); return null;
            case "clipboard.readText": this.usedPermissions.add("clipboard.read"); return this.clipboard;
            case "clipboard.writeText": this.clipboard = key; return null;
            case "selection.replace": this.usedPermissions.add("selection.replace"); this.replacements.push(key); return null;
            case "text.segment":
                if (args[1] !== "word" && args[1] !== "sentence") throw new Refusal("invalid_argument", "The unit is word or sentence", { path: "/1" });
                return segment(key, args[1]);
            case "ui.toast": this.toasts.push({ message: key, kind: String(args[1] ?? "info") }); return null;
            case "ui.openUrl":
                if (!/^(https?|mailto):/i.test(key)) throw new Refusal("invalid_argument", `openUrl takes https, http and mailto URLs, not ${key}`, { path: "/0" });
                this.openedURLs.push(key);
                return null;
            case "ui.openSettings": return null;
            case "ui.openWebView": {
                const path = key.replace(/^\.\//, "");
                if (!path || path.startsWith("/") || path.includes("://") || path.split("/").includes("..")) {
                    throw new Refusal("not_found", `${key} isn't a file in the plugin's package`, { path: "/0" });
                }
                const id = `view-${this.views.length + 1}`;
                this.views.push({ id, path, data: (args[1] as { data?: unknown } | undefined)?.data ?? null, messages: [], open: true });
                return id;
            }
            case "ui.postMessage": this.openView(key).messages.push(args[1]); return null;
            case "ui.closeView": this.openView(key).open = false; return null;
            case "ui.show": throw new Refusal("unavailable", "Native views come after ODH; use openWebView");
            case "permissions.query":
                return Object.fromEntries((args[0] as string[]).map((n) => [n, this.state(n)]));
            case "permissions.request": {
                for (const name of args[0] as string[]) {
                    if (!this.mayRequest(name) || name === "network:*") throw new Refusal("invalid_argument", `${name} can't be requested`, { permission: name });
                    if (this.state(name) !== "prompt") continue;
                    this.prompts.push(name);
                    if (this.promptAnswer === "deny") this.denied.add(name);
                    else this.granted.add(name);
                }
                return (args[0] as string[]).filter((n) => this.state(n) === "granted");
            }
            default:
                throw new Refusal("invalid_argument", `host.${ns}.${method} doesn't exist`);
        }
    }

    private optionalNetwork(name: string): boolean {
        return name.startsWith("network:") && (this.manifest.optionalPermissions ?? []).includes("network:*" as never);
    }

    private async fetch(url: string, init: Record<string, unknown>) {
        if (!/^https?:\/\//i.test(url)) throw new Refusal("invalid_argument", "Only http and https URLs can be fetched", { path: "/0" });
        const covering = [...(this.manifest.permissions ?? []), ...this.granted].find((p) => networkPermissionCovers(p, url));
        if (!covering) {
            const permission = networkPermissionFor(url);
            throw new Refusal("permission_denied", `${permission} isn't granted`, { permission, requestable: this.optionalNetwork(permission) });
        }
        this.usedPermissions.add(covering);
        const found = this.routes.find(({ match }) => (typeof match === "string" ? match === url : match.test(url)));
        if (!found) throw new Refusal("network_error", `No mock answers ${url}`, { reason: "unmocked" });
        const body = init["body"] as { $bytes?: string } | string | undefined;
        const request = {
            url,
            method: String(init["method"] ?? "GET"),
            headers: (init["headers"] ?? {}) as Record<string, string>,
            ...(body !== undefined ? { body: typeof body === "string" ? new TextEncoder().encode(body) : Uint8Array.from(Buffer.from(body.$bytes ?? "", "base64")) } : {}),
        };
        const response = typeof found.route === "function" ? await found.route(request) : found.route;
        const bytes = typeof response.body === "string" ? new TextEncoder().encode(response.body) : response.body ?? new Uint8Array();
        const headers = Object.fromEntries(Object.entries(response.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v]));
        return { status: response.status ?? 200, url, headers, body: init["responseType"] === "bytes" ? { $bytes: bytesToBase64(bytes) } : new TextDecoder().decode(bytes) };
    }
}

function segment(text: string, unit: "word" | "sentence"): Array<{ start: number; end: number }> {
    const segmenter = new Intl.Segmenter(undefined, { granularity: unit });
    const out: Array<{ start: number; end: number }> = [];
    for (const piece of segmenter.segment(text)) {
        if (unit === "word" && !piece.isWordLike) continue;
        out.push({ start: piece.index, end: piece.index + piece.segment.length });
    }
    return out;
}

/** What each host method needs, as Baron's HostMethodRequirement says: [permission, needs a click]. */
const requirements: Record<string, [string | undefined, boolean]> = {
    "clipboard.readText": ["clipboard.read", true],
    "clipboard.writeText": [undefined, true],
    "selection.replace": ["selection.replace", true],
    "secrets.get": ["secrets", false], "secrets.set": ["secrets", false], "secrets.remove": ["secrets", false],
    "ui.openUrl": [undefined, true], "ui.openWebView": [undefined, true], "ui.show": [undefined, true],
    "permissions.request": [undefined, true],
};
