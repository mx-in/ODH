import { afterEach, expect, test } from "bun:test";
import { join } from "node:path";
import { createHarness, type Harness } from "@baron/test";

const api = (word: string) => `https://dict.youdao.com/suggest?num=5&doctype=json&q=${word}`;
const answer = (entries: Array<{ entry: string; explain: string }>) => ({ body: JSON.stringify({ data: { entries } }), headers: { "content-type": "application/json" } });

let h: Harness | undefined;
afterEach(() => h?.close());
const harness = async () => (h = await createHarness({ plugin: join(import.meta.dir, "..") }));

test("opens the definitions in the panel", async () => {
    const h = await harness();
    h.http.mock(api("fox"), answer([{ entry: "fox", explain: "n. 狐狸" }, { entry: "foxes", explain: "n. 狐狸（复数）" }]));
    expect(await h.runAction("define", { text: " Fox " })).toBeUndefined();
    expect(h.views.opened).toHaveLength(1);
    expect(h.views.opened[0]).toMatchObject({ path: "views/panel.html", data: { word: "fox", entries: [{ entry: "fox" }, { entry: "foxes" }] } });
});

test("copies a definition when the page asks, and tells the page", async () => {
    const h = await harness();
    h.http.mock(api("fox"), answer([{ entry: "fox", explain: "n. 狐狸" }]));
    await h.runAction("define", { text: "fox" });
    const view = h.views.opened[0]!;
    h.views.send(view.id, { copy: "fox: n. 狐狸" });
    await Bun.sleep(30);
    expect(h.host.clipboard).toBe("fox: n. 狐狸");
    expect(view.messages).toEqual([{ copied: "fox: n. 狐狸" }]);
});

test("keeps to toasts when there is nothing to show", async () => {
    const h = await harness();
    h.http.mock(api("qwzx"), answer([]));
    expect(await h.runAction("define", { text: "qwzx" })).toEqual({ type: "toast", message: "No definition found for “qwzx”." });
    expect(h.views.opened).toHaveLength(0);
});
