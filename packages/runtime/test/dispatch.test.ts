import { describe, expect, test } from "bun:test";
import { BaronError, definePlugin, type DispatchEnvelope, type PluginDefinition } from "@baron/api";
import { Channel } from "../src/channel.ts";
import { Dispatcher } from "../src/dispatch.ts";
import { Views } from "../src/host.ts";

const environment = { apiVersion: 1, baronVersion: "0.1.0", pluginVersion: "1.0.0", platform: "macos", locale: "en", appearance: "light", development: false } as const;
const context = { text: "fox", source: "ax-text", editable: true, app: { id: "a", name: "A", pid: 1 }, platform: "macos" } as const;

function setup(plugin: PluginDefinition | undefined) {
    const sent: any[] = [];
    const channel = new Channel({ send: (json) => sent.push(JSON.parse(json)), setTimer() {}, clearTimer() {}, randomBytes: () => [] });
    const dispatcher = new Dispatcher(channel, new Views(), () => plugin);
    const run = async (target: DispatchEnvelope["target"], name: string, extra: Partial<DispatchEnvelope["payload"]> = {}) => {
        await dispatcher.dispatch({ v: 1, kind: "dispatch", id: 7, target, name, payload: { environment, preferences: { deck: "D" }, ...extra } });
        return sent.at(-1);
    };
    return { run, dispatcher, sent };
}

describe("Dispatcher", () => {
    const plugin = definePlugin({
        actions: {
            upper: (ctx) => ({ type: "replace", text: ctx.text.toUpperCase() }),
            fails: () => { throw new Error("no dictionary"); },
            denied: () => { throw new BaronError("permission_denied", "nope", { permission: "network:x" }); },
            cyclic: () => { const a: any = {}; a.a = a; return a; },
            bytes: () => ({ type: "copy", text: "x", raw: new Uint8Array([1]) }) as any,
        },
        options: { decks: (prefs) => [{ value: String(prefs["deck"]), title: "Deck" }] },
        buttons: { test: () => ({ message: "ok" }) },
        lifecycle: { onUpdate: ({ previousVersion }) => { seen.push(previousVersion); } },
    });
    const seen: string[] = [];

    test("runs an action with the context and replies with its result", async () => {
        expect(await setup(plugin).run("action", "upper", { context })).toEqual({ v: 1, kind: "result", id: 7, ok: true, value: { type: "replace", text: "FOX" } });
    });

    test("gives options providers and buttons the preferences", async () => {
        const { run } = setup(plugin);
        expect((await run("options", "decks")).value).toEqual([{ value: "D", title: "Deck" }]);
        expect((await run("button", "test")).value).toEqual({ message: "ok" });
    });

    test("runs lifecycle hooks, and treats a missing one as done", async () => {
        const { run } = setup(plugin);
        expect((await run("lifecycle", "onUpdate", { args: [{ previousVersion: "0.9.0" }] })).ok).toBe(true);
        expect(seen).toEqual(["0.9.0"]);
        expect((await run("lifecycle", "onInstall")).ok).toBe(true);
    });

    test("classifies failures", async () => {
        const { run } = setup(plugin);
        const thrown = await run("action", "fails", { context });
        expect(thrown.error.code).toBe("plugin_error");
        expect(thrown.error.message).toBe("no dictionary");
        expect(thrown.error.stack).toContain("no dictionary");
        expect((await run("action", "denied", { context })).error).toEqual({ code: "permission_denied", message: "nope", data: { permission: "network:x" } });
        expect((await run("action", "missing", { context })).error.code).toBe("not_found");
        expect((await run("action", "cyclic", { context })).error.message).toContain("can't be sent");
        expect((await setup(undefined).run("action", "upper", { context })).error.code).toBe("not_found");
    });

    test("encodes bytes in results", async () => {
        expect((await setup(plugin).run("action", "bytes", { context })).value.raw).toEqual({ $bytes: "AQ==" });
    });

    test("cancel aborts the dispatch's signal", async () => {
        let signal: AbortSignal | undefined;
        const slow = definePlugin({ actions: { wait: (_ctx, host) => new Promise((resolve) => { signal = host.signal; host.signal.addEventListener("abort", () => resolve(undefined)); }) } });
        const { dispatcher } = setup(slow);
        const running = dispatcher.dispatch({ v: 1, kind: "dispatch", id: 9, target: "action", name: "wait", payload: { environment, preferences: {}, context } });
        expect(dispatcher.runningCount).toBe(1);
        dispatcher.cancel(9);
        await running;
        expect(signal?.aborted).toBe(true);
        expect(dispatcher.runningCount).toBe(0);
    });
});
