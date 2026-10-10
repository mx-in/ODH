import { describe, expect, test } from "bun:test";
import { definePlugin } from "@baron/api";
import { Channel } from "../src/channel.ts";
import { Dispatcher } from "../src/dispatch.ts";
import { Views } from "../src/host.ts";
import { AbortController, AbortSignal, EventTarget, Event } from "../src/polyfills/abort.ts";

describe("AbortController", () => {
    test("aborts once, with an AbortError by default, telling listeners and onabort", () => {
        const controller = new AbortController();
        const seen: string[] = [];
        controller.signal.addEventListener("abort", () => seen.push("listener"));
        controller.signal.onabort = () => seen.push("onabort");
        controller.abort();
        controller.abort("again");
        expect(seen).toEqual(["listener", "onabort"]);
        expect(controller.signal.aborted).toBe(true);
        expect((controller.signal.reason as Error).name).toBe("AbortError");
        expect(() => controller.signal.throwIfAborted()).toThrow();
    });

    test("keeps a custom reason", () => {
        const controller = new AbortController();
        controller.abort("stop");
        expect(controller.signal.reason).toBe("stop");
    });

    test("AbortSignal.abort, timeout and any", async () => {
        expect(AbortSignal.abort("x").reason).toBe("x");
        const timed = AbortSignal.timeout(5);
        await new Promise((r) => setTimeout(r, 20));
        expect((timed.reason as Error).name).toBe("TimeoutError");
        const a = new AbortController(), b = new AbortController();
        const either = AbortSignal.any([a.signal, b.signal]);
        b.abort("b");
        expect(either.reason).toBe("b");
    });
});

describe("EventTarget", () => {
    test("once listeners run once and duplicates are ignored", () => {
        const target = new EventTarget();
        let count = 0;
        const listener = () => count++;
        target.addEventListener("ping", listener, { once: true });
        target.addEventListener("ping", listener, { once: true });
        target.dispatchEvent(new Event("ping"));
        target.dispatchEvent(new Event("ping"));
        expect(count).toBe(1);
    });
});

test("a cancelled dispatch aborts the handler's signal (with the polyfill)", async () => {
    const original = globalThis.AbortController;
    (globalThis as any).AbortController = AbortController;
    try {
        let reason: unknown;
        const plugin = definePlugin({ actions: { wait: (_ctx, host) => new Promise((resolve) => host.signal.addEventListener("abort", () => resolve((reason = host.signal.reason, undefined)))) } });
        const channel = new Channel({ send() {}, setTimer() {}, clearTimer() {}, randomBytes: () => [] });
        const dispatcher = new Dispatcher(channel, new Views(), () => plugin);
        const env = { apiVersion: 1, baronVersion: "0", pluginVersion: "1", platform: "macos", locale: "en", appearance: "light", development: false } as const;
        const running = dispatcher.dispatch({ v: 1, kind: "dispatch", id: 1, target: "action", name: "wait", payload: { environment: env, preferences: {}, context: { text: "x", source: "ax-text", editable: false, app: { id: "a", name: "A", pid: 1 }, platform: "macos" } } });
        dispatcher.cancel(1);
        await running;
        expect((reason as Error).message).toBe("The dispatch was cancelled");
    } finally {
        globalThis.AbortController = original;
    }
});
