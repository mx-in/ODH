import { describe, expect, test } from "bun:test";
import { Channel } from "../src/channel.ts";
import { formatValue } from "../src/format.ts";
import { createHost, Views } from "../src/host.ts";

const environment = { apiVersion: 1, baronVersion: "0.1.0", pluginVersion: "1.0.0", platform: "macos", locale: "en", appearance: "light", development: false } as const;

function setup() {
    const sent: any[] = [];
    const channel = new Channel({ send: (json) => sent.push(JSON.parse(json)), setTimer() {}, clearTimer() {}, randomBytes: () => [], digest: () => "" });
    const views = new Views();
    const host = createHost(channel, views, { environment, preferences: { deck: "Default" }, signal: new AbortController().signal });
    const answer = (value?: unknown) => channel.receive(JSON.stringify({ v: 1, kind: "result", id: sent.at(-1).id, ok: true, value }));
    return { channel, views, host, sent, answer };
}

describe("host object", () => {
    test("exposes environment and preferences synchronously, read-only", () => {
        const { host } = setup();
        expect(host.environment.locale).toBe("en");
        expect(host.preferences["deck"]).toBe("Default");
        expect(Object.isFrozen(host.preferences) && Object.isFrozen(host)).toBe(true);
    });

    test("turns each method into one call", async () => {
        const { host, sent, answer } = setup();
        const value = host.storage.get<string[]>("history");
        expect(sent[0]).toMatchObject({ kind: "call", ns: "storage", method: "get", args: ["history"] });
        answer(["fox"]);
        expect(await value).toEqual(["fox"]);

        const fetched = host.http.fetch("https://dict.example/fox", { method: "GET" });
        expect(sent[1]).toMatchObject({ ns: "http", method: "fetch", args: ["https://dict.example/fox", { method: "GET" }] });
        answer({ status: 200, url: "https://dict.example/fox", headers: {}, body: "a fox" });
        expect((await fetched).body).toBe("a fox");

        const toast = host.ui.toast("hi");
        expect(sent[2]).toMatchObject({ ns: "ui", method: "toast", args: ["hi", "info"] });
        answer();
        expect(await toast).toBeUndefined();
    });

    test("missing keys read as undefined, not null", async () => {
        const { host, answer } = setup();
        const missing = host.storage.get("nothing");
        answer(null);
        expect(await missing).toBeUndefined();
        const cached = host.cache.get("nothing");
        answer(null);
        expect(await cached).toBeUndefined();
    });

    test("log lines are formatted text and need no answer", () => {
        const { host, sent, channel } = setup();
        host.log.warn("count", 3, { a: [1] });
        expect(sent[0]).toMatchObject({ ns: "log", method: "warn", args: ['count 3 {"a":[1]}'] });
        expect(channel.pendingCount).toBe(1);
    });

    test("views deliver messages and closing", async () => {
        const { host, views, answer } = setup();
        const opening = host.ui.openWebView("views/popup.html", { data: { word: "fox" } });
        answer("v1");
        const view = await opening;
        const messages: unknown[] = [];
        view.onMessage((m) => messages.push(m));
        views.deliver("v1", "message", { add: "fox" });
        views.deliver("v1", "closed", null);
        await view.closed;
        expect(messages).toEqual([{ add: "fox" }]);
    });
});

describe("formatValue", () => {
    test("prints values like a console, surviving cycles", () => {
        const cycle: any = { name: "a" };
        cycle.self = cycle;
        expect(formatValue(cycle)).toBe('{"name":"a","self":"[Circular]"}');
        expect(formatValue(new Uint8Array(3))).toBe('"Uint8Array(3)"');
        expect(formatValue(undefined)).toBe("undefined");
        expect(formatValue(10n)).toBe("10n");
        expect(formatValue(function named() {})).toBe("[Function named]");
    });
});
