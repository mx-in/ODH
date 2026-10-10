import { afterEach, expect, test } from "bun:test";
import { join } from "node:path";
import { createHarness, type Harness } from "@baron/test";

let h: Harness | undefined;
afterEach(() => h?.close());

test("replaces the selection with capitals", async () => {
    h = await createHarness({ plugin: join(import.meta.dir, "..") });
    expect(await h.runAction("uppercase", { text: "the quick fox", editable: true })).toEqual({ type: "replace", text: "THE QUICK FOX" });
});

test("handles letters beyond ASCII", async () => {
    h = await createHarness({ plugin: join(import.meta.dir, "..") });
    expect(await h.runAction("uppercase", { text: "straße naïve ǆ", editable: true })).toEqual({ type: "replace", text: "STRASSE NAÏVE Ǆ" });
});

test("uses no network and no other permission", async () => {
    h = await createHarness({ plugin: join(import.meta.dir, "..") });
    await h.runAction("uppercase", { text: "fox", editable: true });
    expect(h.permissions.used).toEqual([]);
});
