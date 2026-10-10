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
    readonly replacements: string[] = [];
    readonly logs: Array<{ level: string; text: string }> = [];
    clipboard = "";
    /** Optional permissions the user has allowed (or allows when asked, if `allowWhenAsked`). */
    readonly granted = new Set<string>();
    allowWhenAsked = false;
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

    private require(name: string): void {
        if (!this.holds(name)) throw new Refusal("permission_denied", `${name} isn't granted`, { permission: name, requestable: false });
        this.usedPermissions.add(name);
    }

    async handle(call: CallEnvelope): Promise<ResultEnvelope> {
        try {
            return { v: 1, kind: "result", id: call.id, ok: true, value: await this.serve(call.ns, call.method, call.args) };
        } catch (error) {
            const refusal = error instanceof Refusal ? error : new Refusal("internal", String(error));
            return { v: 1, kind: "result", id: call.id, ok: false, error: { code: refusal.code, message: refusal.message, ...(refusal.data ? { data: refusal.data } : {}) } };
        }
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
            case "secrets.get": this.require("secrets"); return this.secrets.get(key) ?? null;
            case "secrets.set": this.require("secrets"); this.secrets.set(key, String(args[1])); return null;
            case "secrets.remove": this.require("secrets"); this.secrets.delete(key); return null;
            case "clipboard.readText": this.require("clipboard.read"); return this.clipboard;
            case "clipboard.writeText": this.clipboard = key; return null;
            case "selection.replace": this.require("selection.replace"); this.replacements.push(key); return null;
            case "text.segment": return segment(key, args[1] === "word" ? "word" : "sentence");
            case "ui.toast": this.toasts.push({ message: key, kind: String(args[1] ?? "info") }); return null;
            case "ui.openUrl": this.openedURLs.push(key); return null;
            case "ui.openSettings": return null;
            case "permissions.query":
                return Object.fromEntries((args[0] as string[]).map((n) => [n, this.holds(n) ? "granted" : (this.manifest.optionalPermissions ?? []).includes(n as never) || this.optionalNetwork(n) ? "prompt" : "denied"]));
            case "permissions.request":
                for (const name of args[0] as string[]) if (this.allowWhenAsked && ((this.manifest.optionalPermissions ?? []).includes(name as never) || this.optionalNetwork(name))) this.granted.add(name);
                return (args[0] as string[]).filter((n) => this.holds(n));
            default:
                throw new Refusal("invalid_argument", `host.${ns}.${method} doesn't exist`);
        }
    }

    private optionalNetwork(name: string): boolean {
        return name.startsWith("network:") && (this.manifest.optionalPermissions ?? []).includes("network:*" as never);
    }

    private async fetch(url: string, init: Record<string, unknown>) {
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
