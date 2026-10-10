/**
 * The page bridge: evaluated in every plugin page before its own scripts, it defines `window.baron`, the same
 * host API the plugin's engine code gets (without clipboard and selection), plus `baron.view`. Calls go to Baron
 * through WebKit's `baron` message handler, which answers each with its result envelope; Baron sends events
 * through `__baronPageReceive`. Baron takes the plugin's identity from the page's origin, never from a message.
 * Design: docs/design/plugin-platform/07-web-views.md#the-page-bridge
 */
import type { Environment, PageHost, PageView, Preferences } from "@baron/api";
import { Channel } from "./channel.ts";
import { createHost, Views } from "./host.ts";
import type { BaronNative } from "./native.ts";

/** What Baron injects just before this script. */
interface PageConfig {
    environment: Environment;
    preferences: Preferences;
    /** The result panel's view id; null for a settings page. */
    view: string | null;
    data: unknown;
}

interface ReplyHandler {
    postMessage(json: string): Promise<string | null>;
}

const page = globalThis as unknown as Record<string, unknown> & { webkit?: { messageHandlers?: { baron?: ReplyHandler } } };
const config = page["__baronPageConfig"] as PageConfig | undefined;
delete page["__baronPageConfig"];
const handler = page.webkit?.messageHandlers?.baron;

if (config && handler) {
    const unsupported = () => {
        throw new Error("Not available in pages");
    };
    const native: BaronNative = {
        send: (json) => void handler.postMessage(json).then((reply) => reply && channel.receive(reply)),
        setTimer: unsupported,
        clearTimer: unsupported,
        randomBytes: unsupported,
        digest: unsupported,
    };
    const channel = new Channel(native);
    const listeners: Array<(message: unknown) => void> = [];
    channel.onEnvelope = (envelope) => {
        if (envelope.kind === "event" && envelope.name === "message") for (const listener of listeners) listener(envelope.payload);
    };
    const host = createHost(channel, new Views(), {
        environment: config.environment,
        preferences: config.preferences,
        signal: new AbortController().signal,
    });
    const call = (method: string, ...args: unknown[]) => channel.call("view", method, args).then(() => undefined);
    const view: PageView | undefined = config.view === null ? undefined : Object.freeze({
        data: config.data,
        postMessage: (message: unknown) => call("postMessage", message),
        onMessage: (listener: (message: unknown) => void) => void listeners.push(listener),
        resize: (height: number) => call("resize", height),
        close: () => call("close"),
    });
    const baron: PageHost = Object.freeze({
        environment: host.environment,
        preferences: host.preferences,
        http: host.http,
        storage: host.storage,
        cache: host.cache,
        secrets: host.secrets,
        text: host.text,
        permissions: host.permissions,
        log: host.log,
        ui: Object.freeze({ toast: host.ui.toast, openUrl: host.ui.openUrl }),
        ...(view ? { view } : {}),
    });
    const define = (name: string, value: unknown) => Object.defineProperty(page, name, { value, enumerable: false, configurable: false, writable: false });
    define("baron", baron);
    define("__baronPageReceive", (json: string) => channel.receive(json));
}
