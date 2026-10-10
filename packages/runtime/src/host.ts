import type { BaronElement, Environment, Host, HttpInit, OptionalPermission, Permission, Preferences, ViewHandle, WebViewOptions } from "@baron/api";
import type { Channel } from "./channel.ts";
import { formatValue } from "./format.ts";

export interface HostState {
    environment: Environment;
    preferences: Preferences;
    signal: AbortSignal;
}

/** Message listeners of open views, fed by `event` envelopes. */
export class Views {
    private readonly listeners = new Map<string, Array<(message: unknown) => void>>();
    private readonly closed = new Map<string, () => void>();

    handle(channel: Channel, view: string): ViewHandle {
        let markClosed!: () => void;
        const closed = new Promise<void>((resolve) => (markClosed = resolve));
        this.closed.set(view, markClosed);
        return {
            postMessage: async (message) => void (await channel.call("ui", "postMessage", [view, message])),
            onMessage: (listener) => void this.listeners.set(view, [...(this.listeners.get(view) ?? []), listener]),
            close: async () => void (await channel.call("ui", "closeView", [view])),
            closed,
        };
    }

    deliver(view: string, name: string, payload: unknown): void {
        if (name === "message") for (const listener of this.listeners.get(view) ?? []) listener(payload);
        if (name === "closed") {
            this.closed.get(view)?.();
            this.closed.delete(view);
            this.listeners.delete(view);
        }
    }
}

/** The `host` object a dispatch's handler receives. Every method is one envelope to Baron. */
export function createHost(channel: Channel, views: Views, state: HostState): Host {
    const call = (ns: string, method: string, ...args: unknown[]) => channel.call(ns, method, args);
    const log = (level: string) => (...values: unknown[]) => channel.notify("log", level, [values.map(formatValue).join(" ")]);
    return Object.freeze({
        environment: Object.freeze({ ...state.environment }),
        preferences: Object.freeze({ ...state.preferences }),
        signal: state.signal,
        http: Object.freeze({
            fetch: ((url: string, init?: HttpInit) => call("http", "fetch", url, init ?? {})) as Host["http"]["fetch"],
        }),
        clipboard: Object.freeze({
            readText: () => call("clipboard", "readText") as Promise<string>,
            writeText: async (text: string) => void (await call("clipboard", "writeText", text)),
        }),
        selection: Object.freeze({
            replace: async (text: string) => void (await call("selection", "replace", text)),
        }),
        storage: Object.freeze({
            // Missing keys come back as null over JSON; the API promises undefined.
            get: async <T>(key: string) => ((await call("storage", "get", key)) ?? undefined) as T | undefined,
            set: async (key: string, value: unknown) => void (await call("storage", "set", key, value)),
            remove: async (key: string) => void (await call("storage", "remove", key)),
            keys: () => call("storage", "keys") as Promise<string[]>,
            usage: () => call("storage", "usage") as Promise<number>,
        }),
        cache: Object.freeze({
            get: async (key: string) => ((await call("cache", "get", key)) ?? undefined) as string | undefined,
            set: async (key: string, value: string) => void (await call("cache", "set", key, value)),
            remove: async (key: string) => void (await call("cache", "remove", key)),
            clear: async () => void (await call("cache", "clear")),
        }),
        secrets: Object.freeze({
            get: async (key: string) => ((await call("secrets", "get", key)) ?? undefined) as string | undefined,
            set: async (key: string, value: string) => void (await call("secrets", "set", key, value)),
            remove: async (key: string) => void (await call("secrets", "remove", key)),
        }),
        text: Object.freeze({
            segment: (text: string, unit: "word" | "sentence") => call("text", "segment", text, unit) as Promise<Array<{ start: number; end: number }>>,
        }),
        ui: Object.freeze({
            toast: async (message: string, kind?: "info" | "success" | "error") => void (await call("ui", "toast", message, kind ?? "info")),
            openUrl: async (url: string) => void (await call("ui", "openUrl", url)),
            openWebView: async (path: string, options?: WebViewOptions) => views.handle(channel, (await call("ui", "openWebView", path, options ?? {})) as string),
            show: async (view: BaronElement) => views.handle(channel, (await call("ui", "show", view)) as string),
            openSettings: async () => void (await call("ui", "openSettings")),
        }),
        permissions: Object.freeze({
            query: (names: OptionalPermission[]) => call("permissions", "query", names) as Promise<Record<string, "granted" | "denied" | "prompt">>,
            request: (names: Permission[]) => call("permissions", "request", names) as Promise<Permission[]>,
        }),
        log: Object.freeze({ debug: log("debug"), info: log("info"), warn: log("warn"), error: log("error") }),
    });
}
