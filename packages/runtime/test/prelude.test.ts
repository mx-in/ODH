import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { buildPrelude, swiftCopy } from "../scripts/build.ts";
import { createSandbox } from "./support/sandbox.ts";

const environment = { apiVersion: 1, baronVersion: "0.1.0", pluginVersion: "1.0.0", platform: "macos", locale: "en", appearance: "light", development: false };
const context = { text: "fox", source: "ax-text", editable: true, app: { id: "a", name: "A", pid: 1 }, platform: "macos" };

describe("the built prelude in a bare context", () => {
    test("Baron's copy is up to date (run npm run build -w packages/runtime)", async () => {
        expect(readFileSync(swiftCopy, "utf8")).toBe(await buildPrelude());
    });

    test("installs the web-platform subset and hides the native object", async () => {
        const box = await createSandbox();
        const kinds = box.run(`[typeof setTimeout, typeof queueMicrotask, typeof URL, typeof TextEncoder, typeof atob, typeof structuredClone,
            typeof AbortController, typeof fetch, typeof Headers, typeof __baronNative, typeof process, typeof require].join()`);
        expect(kinds).toBe("function,function,function,function,function,function,function,function,function,undefined,undefined,undefined");
        expect(() => box.run("__baronReceive = null; 'x'")).not.toThrow();
        expect(typeof box.run("__baronReceive")).toBe("function");
    });

    test("runs a plugin's action end to end, including a host call", async () => {
        const box = await createSandbox();
        box.run(`globalThis.__baronPlugin = { actions: { async shout(ctx, host) {
            const stored = await host.storage.get("suffix");
            return { type: "replace", text: ctx.text.toUpperCase() + stored };
        } } };`);
        box.deliver({ v: 1, kind: "dispatch", id: 5, target: "action", name: "shout", payload: { environment, preferences: {}, context } });
        const call = await box.waitFor((e) => e.kind === "call" && e.ns === "storage");
        box.deliver({ v: 1, kind: "result", id: call.id, ok: true, value: "!" });
        expect(await box.waitFor((e) => e.kind === "result" && e.id === 5)).toEqual({ v: 1, kind: "result", id: 5, ok: true, value: { type: "replace", text: "FOX!" } });
    });

    test("timers and console work through the native side", async () => {
        const box = await createSandbox();
        box.run(`setTimeout(() => console.log("tick", new URL("https://a.example/b?c=1").searchParams.get("c")), 5)`);
        expect(await box.waitFor((e) => e.ns === "log")).toMatchObject({ method: "info", args: ["tick 1"] });
    });

    test("an uncaught timer error is logged, not fatal", async () => {
        const box = await createSandbox();
        box.run(`setTimeout(() => { throw new Error("late") }, 0)`);
        expect((await box.waitFor((e) => e.ns === "log")).args[0]).toContain("Uncaught Error: late");
    });
});
