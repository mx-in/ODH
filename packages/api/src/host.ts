/**
 * `host`, the only door from plugin code to the system (apiVersion 1).
 * Every call is checked against the plugin's permissions in Baron.
 * Design: docs/design/plugin-platform/03-host-api-and-ipc.md
 */
import type { ToastKind } from "./context.ts";
import type { OptionalPermission, Permission, Platform, PreferenceValue } from "./manifest.ts";

export interface Environment {
    readonly apiVersion: 1;
    readonly baronVersion: string;
    readonly pluginVersion: string;
    readonly platform: Platform;
    /** BCP 47, such as `zh-Hans`. */
    readonly locale: string;
    readonly appearance: "light" | "dark";
    /** True under `baron dev`. */
    readonly development: boolean;
}

/** Values of the declared preferences; `secret` preferences are read with `host.secrets.get(id)` instead. */
export type Preferences = Readonly<Record<string, PreferenceValue | undefined>>;

export type HttpMethod = "GET" | "HEAD" | "POST" | "PUT" | "PATCH" | "DELETE";

export interface HttpInit {
    method?: HttpMethod;
    headers?: Record<string, string>;
    body?: string | Uint8Array;
    /** Milliseconds; 30,000 by default and 60,000 at most. */
    timeout?: number;
    /** How to return the body: decoded as UTF-8 text (the default) or as bytes. */
    responseType?: "text" | "bytes";
}

/** Non-2xx statuses are responses, not errors, as in browsers. */
export interface HttpResponse<Body = string> {
    status: number;
    /** The final URL, after redirects. */
    url: string;
    /** Header names in lower case. */
    headers: Record<string, string>;
    body: Body;
}

export interface Http {
    /** Only to hosts the plugin's `network:` permissions allow; each redirect is checked too. */
    fetch(url: string, init?: HttpInit & { responseType?: "text" }): Promise<HttpResponse<string>>;
    fetch(url: string, init: HttpInit & { responseType: "bytes" }): Promise<HttpResponse<Uint8Array>>;
}

/** A native view element, built with `@baron/ui` (after ODH). */
export interface BaronElement {
    readonly type: unknown;
    readonly props: unknown;
    readonly key: string | null;
}

/** An open result panel, seen from the plugin's engine context. */
export interface ViewHandle {
    postMessage(message: unknown): Promise<void>;
    onMessage(listener: (message: unknown) => void): void;
    close(): Promise<void>;
    /** Settles when the panel closes, for any reason. */
    readonly closed: Promise<void>;
}

export interface WebViewOptions {
    /** Passed to the page as `baron.view.data`. */
    data?: unknown;
    width?: number;
    height?: number;
}

export type PermissionState = "granted" | "denied" | "prompt";

export interface Host {
    readonly environment: Environment;
    /** A snapshot taken before each dispatch. */
    readonly preferences: Preferences;
    /** Aborted when this dispatch runs out of time or its caller goes away. */
    readonly signal: AbortSignal;
    readonly http: Http;
    readonly clipboard: {
        /** Needs `clipboard.read` and a user action. */
        readText(): Promise<string>;
        /** Needs a user action. */
        writeText(text: string): Promise<void>;
    };
    readonly selection: {
        /** Needs `selection.replace`, a user action and an editable selection. */
        replace(text: string): Promise<void>;
    };
    /** JSON values, private to the plugin; 5 MB in total, 1 MB per value. */
    readonly storage: {
        get<T>(key: string): Promise<T | undefined>;
        set(key: string, value: unknown): Promise<void>;
        remove(key: string): Promise<void>;
        keys(): Promise<string[]>;
        /** Bytes used, keys plus values. */
        usage(): Promise<number>;
    };
    /** Strings Baron may evict at any time; 10 MB in total, 2 MB per value. */
    readonly cache: {
        get(key: string): Promise<string | undefined>;
        set(key: string, value: string): Promise<void>;
        remove(key: string): Promise<void>;
        clear(): Promise<void>;
    };
    /** Keychain items on this Mac; needs `secrets`. */
    readonly secrets: {
        get(key: string): Promise<string | undefined>;
        set(key: string, value: string): Promise<void>;
        remove(key: string): Promise<void>;
    };
    readonly text: {
        /** Word or sentence boundaries as UTF-16 offsets, using the system's segmenter. */
        segment(text: string, unit: "word" | "sentence"): Promise<Array<{ start: number; end: number }>>;
    };
    readonly ui: {
        toast(message: string, kind?: ToastKind): Promise<void>;
        /** `https`, `http` and `mailto` only; needs a user action. */
        openUrl(url: string): Promise<void>;
        /** Opens a page from the package in the result panel; needs a user action. */
        openWebView(path: string, options?: WebViewOptions): Promise<ViewHandle>;
        /** Shows a native view in the result panel (after ODH); needs a user action. */
        show(view: BaronElement): Promise<ViewHandle>;
        openSettings(): Promise<void>;
    };
    readonly permissions: {
        query(names: OptionalPermission[]): Promise<Record<string, PermissionState>>;
        /** Asks the user for permissions listed in `optionalPermissions`; returns the ones granted afterwards. Needs a user action. */
        request(names: Permission[]): Promise<Permission[]>;
    };
    /** Plugin log lines are private in the system log and shown in full under `baron dev`. */
    readonly log: {
        debug(...values: unknown[]): void;
        info(...values: unknown[]): void;
        warn(...values: unknown[]): void;
        error(...values: unknown[]): void;
    };
}

/** `baron.view` in a page shown in the result panel. Design: docs/design/plugin-platform/07-web-views.md#the-page-bridge */
export interface PageView {
    /** The `data` passed to `openWebView`. */
    readonly data: unknown;
    /** Sends a message to the plugin's code, which gets it through its `ViewHandle.onMessage`. */
    postMessage(message: unknown): Promise<void>;
    /** Messages the plugin's code sent with `ViewHandle.postMessage`. */
    onMessage(listener: (message: unknown) => void): void;
    /** Asks for this content height in points; the panel grows up to 640 points, then the page scrolls. */
    resize(height: number): Promise<void>;
    close(): Promise<void>;
}

/** `window.baron` in a plugin page: the host API without clipboard and selection, with the same permissions. */
export interface PageHost extends Pick<Host, "environment" | "preferences" | "http" | "storage" | "cache" | "secrets" | "text" | "permissions" | "log"> {
    readonly ui: Pick<Host["ui"], "toast" | "openUrl">;
    /** Only in the result panel; settings pages have none. */
    readonly view?: PageView;
}
