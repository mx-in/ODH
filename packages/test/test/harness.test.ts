import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { createHarness, DispatchError } from "../src/index.ts";

const plugin = join(import.meta.dir, "fixtures", "lookup");

describe.each(["jsc", "quickjs"] as const)("harness on %s", (engine) => {
    test("runs an action through fetch, storage and preferences", async () => {
        const h = await createHarness({ plugin, engine });
        h.http.mock("https://dict.example/word/fox", { body: "<p>a small wild dog</p>" });
        expect(await h.runAction("lookup", { text: "fox" })).toEqual({ type: "toast", message: "def: a small wild dog" });
        expect(h.permissions.used).toEqual(["network:dict.example"]);
        expect(h.host.storage.get("last")).toBe("fox");
        h.close();
    });

    test("uses an action's run name and preference overrides", async () => {
        const h = await createHarness({ plugin, engine, preferences: { prefix: ">" } });
        expect(await h.runAction("upper", { text: "fox" })).toEqual({ type: "replace", text: "FOX" });
        expect(await h.runOptions("prefixes")).toEqual([{ value: ">", title: "Current" }]);
        h.close();
    });

    test("timers work, undeclared hosts are refused, and plugin errors reject with DispatchError", async () => {
        const h = await createHarness({ plugin, engine });
        h.manifest.actions.push({ id: "later", title: "Later" }, { id: "broken", title: "Broken" }, { id: "leaks", title: "Leaks" });
        expect(await h.runAction("later", { text: "x" })).toEqual({ type: "copy", text: "later" });
        expect(await h.runAction("leaks", { text: "x" })).toEqual({ type: "copy", text: "refused" });
        const error = await h.runAction("broken", { text: "x" }).catch((e: unknown) => e);
        expect(error).toBeInstanceOf(DispatchError);
        expect((error as DispatchError).code).toBe("plugin_error");
        h.close();
    });
});

describe.each(["jsc", "quickjs"] as const)("prelude crypto on %s", (engine) => {
    test("digests match the platform", async () => {
        const { mkdtempSync, cpSync, mkdirSync, writeFileSync } = await import("node:fs");
        const scratch = join(import.meta.dir, "..", ".tmp");
        mkdirSync(scratch, { recursive: true });
        const folder = mkdtempSync(join(scratch, "digest-"));
        cpSync(plugin, folder, { recursive: true });
        writeFileSync(join(folder, "src/main.ts"), `export default { actions: { lookup: async (ctx: { text: string }) => {
            const out: string[] = [];
            for (const a of ["SHA-1", "SHA-256", "SHA-384", "SHA-512"]) {
                const b = new Uint8Array(await crypto.subtle.digest(a, new TextEncoder().encode(ctx.text)));
                out.push(Array.from(b, (x) => x.toString(16).padStart(2, "0")).join(""));
            }
            return { type: "copy", text: out.join(" ") + " " + crypto.randomUUID().length };
        } } };`);
        const h = await createHarness({ plugin: folder, engine });
        const text = "狐 fox ".repeat(40);
        const expected = await Promise.all(["SHA-1", "SHA-256", "SHA-384", "SHA-512"].map(async (a) =>
            Array.from(new Uint8Array(await crypto.subtle.digest(a, new TextEncoder().encode(text))), (x) => x.toString(16).padStart(2, "0")).join("")));
        expect(await h.runAction("lookup", { text })).toEqual({ type: "copy", text: `${expected.join(" ")} 36` });
        h.close();
    });
});
