/**
 * The prelude: evaluated in every plugin context before the plugin's bundle, identically on every engine.
 * It needs one global, `__baronNative` (see native.ts), which it takes and removes, and it defines the
 * entry points `__baronReceive` and `__baronFireTimer`. Design: docs/design/plugin-platform/02-runtime.md
 */
import type { PluginDefinition } from "@baron/api";
import { Channel } from "./channel.ts";
import { createConsole } from "./console.ts";
import { Dispatcher } from "./dispatch.ts";
import { Views } from "./host.ts";
import type { BaronNative } from "./native.ts";
import { installAbort } from "./polyfills/abort.ts";
import { installEncoding } from "./polyfills/encoding.ts";
import { installFetch } from "./polyfills/fetch.ts";
import { installURL } from "./polyfills/url.ts";
import { Timers } from "./timers.ts";

const global = globalThis as unknown as Record<string, unknown>;
const native = global["__baronNative"] as BaronNative | undefined;
if (!native) throw new Error("The Baron prelude needs __baronNative");
delete global["__baronNative"];

const channel = new Channel(native);
const console = createConsole(channel);
const report = (error: unknown) => console.error("Uncaught", error);
const timers = new Timers(native, report);
const views = new Views();
const dispatcher = new Dispatcher(channel, views, () => global["__baronPlugin"] as PluginDefinition | undefined);

timers.install(global);
installURL(global);
installEncoding(global);
installAbort(global);
installFetch(global, channel);
global["console"] = console;

channel.onEnvelope = (envelope) => {
    switch (envelope.kind) {
        case "dispatch": void dispatcher.dispatch(envelope); break;
        case "cancel": dispatcher.cancel(envelope.id); break;
        case "event": views.deliver(envelope.view, envelope.name, envelope.payload); break;
        case "call": channel.send({ v: 1, kind: "result", id: envelope.id, ok: false, error: { code: "invalid_argument", message: "Plugins don't serve calls" } });
    }
};

const entry = (name: string, value: unknown) => Object.defineProperty(global, name, { value, enumerable: false, configurable: false, writable: false });
entry("__baronReceive", (json: string) => channel.receive(json));
entry("__baronFireTimer", (id: number) => timers.fire(id));
/** For tests and the runtime's idle check: whether anything is still waiting. */
entry("__baronBusy", () => dispatcher.runningCount > 0 || channel.pendingCount > 0);
