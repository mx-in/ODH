import { expect, test } from "bun:test";
import { join } from "node:path";
import { createHarness } from "@baron/test";

test("uppercases on the engine baron test chose", async () => {
    const h = await createHarness({ plugin: join(import.meta.dir, "..") });
    expect(await h.runAction("upper", { text: "fox" })).toEqual({ type: "replace", text: "FOX" });
    console.log(`ENGINE=${h.engine}`);
    h.close();
});
