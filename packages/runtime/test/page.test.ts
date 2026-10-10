import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";
import { buildPageBridge, pageBridgeCopy } from "../scripts/build.ts";

const environment = { apiVersion: 1, baronVersion: "0.1.0", pluginVersion: "1.0.0", platform: "macos", locale: "en", appearance: "dark", development: false };

/** A bare context standing in for a page: the bridge, a recorded WebKit handler, and Baron's replies. */
async function page(view: string | null, answer: (call: { id: number; ns: string; method: string; args: unknown[] }) => unknown = () => null) {
    const sent: Array<{ id: number; ns: string; method: string; args: unknown[] }> = [];
    const context = createContext({
        AbortController, // pages have it; a bare context doesn't
        __baronPageConfig: { environment, preferences: { deck: "Default" }, view, data: { word: "fox" } },
        webkit: { messageHandlers: { baron: { postMessage: async (json: string) => {
            const call = JSON.parse(json);
            sent.push(call);
            return JSON.stringify({ v: 1, kind: "result", id: call.id, ok: true, value: answer(call) });
        } } } },
    });
    runInContext(await buildPageBridge(), context);
    return { run: (code: string) => runInContext(code, context), sent };
}

describe("the page bridge", () => {
    test("Baron's copy is up to date (run npm run build -w packages/runtime)", async () => {
        expect(readFileSync(pageBridgeCopy, "utf8")).toBe(await buildPageBridge());
    });

    test("gives the page the host API without clipboard and selection, and hides its config", async () => {
        const p = await page("view-1");
        expect(p.run("Object.keys(baron).sort().join()")).toBe("cache,environment,http,log,permissions,preferences,secrets,storage,text,ui,view");
        expect(p.run("Object.keys(baron.ui).sort().join()")).toBe("openUrl,toast");
        expect(p.run("[baron.environment.appearance, baron.preferences.deck, baron.view.data.word, typeof __baronPageConfig].join()")).toBe("dark,Default,fox,undefined");
        expect(() => p.run("baron = null")).not.toThrow();
        expect(p.run("typeof baron.http.fetch")).toBe("function");
    });

    test("sends host calls as envelopes and resolves them with Baron's answer", async () => {
        const p = await page("view-1", (call) => (call.ns === "storage" ? "stored" : null));
        expect(await p.run(`baron.storage.get("k")`)).toBe("stored");
        await p.run(`baron.view.resize(280)`);
        await p.run(`baron.view.postMessage({ add: "fox" })`);
        expect(p.sent.map((c) => [c.ns, c.method, c.args])).toEqual([
            ["storage", "get", ["k"]], ["view", "resize", [280]], ["view", "postMessage", [{ add: "fox" }]],
        ]);
    });

    test("delivers the plugin's messages to onMessage listeners", async () => {
        const p = await page("view-1");
        p.run(`globalThis.got = []; baron.view.onMessage((m) => got.push(m.text))`);
        p.run(`__baronPageReceive(${JSON.stringify(JSON.stringify({ v: 1, kind: "event", view: "view-1", name: "message", payload: { text: "hi" } }))})`);
        expect(p.run("got.join()")).toBe("hi");
    });

    test("a settings page has no view", async () => {
        expect((await page(null)).run("typeof baron.view")).toBe("undefined");
    });
});
