import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { createHarness, DispatchError } from "../src/index.ts";

const plugin = join(import.meta.dir, "fixtures", "lookup");

describe.each(["jsc"] as const)("harness on %s", (engine) => {
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
