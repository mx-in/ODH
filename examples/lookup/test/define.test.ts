import { afterEach, expect, test } from "bun:test";
import { join } from "node:path";
import { createHarness, type Harness } from "@baron/test";

const api = (word: string) => `https://dict.youdao.com/suggest?num=1&doctype=json&q=${word}`;
const answer = (entries: Array<{ entry: string; explain: string }>) => ({ body: JSON.stringify({ result: { code: 200 }, data: { entries } }), headers: { "content-type": "application/json" } });

let h: Harness | undefined;
afterEach(() => h?.close());
const harness = async () => (h = await createHarness({ plugin: join(import.meta.dir, "..") }));

test("shows the definition of the selected word", async () => {
    const h = await harness();
    h.http.mock(api("fox"), answer([{ entry: "fox", explain: "n. 狐狸；狡猾的人" }]));
    expect(await h.runAction("define", { text: " Fox " })).toEqual({ type: "toast", message: "fox: n. 狐狸；狡猾的人" });
    expect(h.permissions.used).toEqual(["network:dict.youdao.com"]);
});

test("says when there's no entry for exactly that word", async () => {
    const h = await harness();
    h.http.mock(api("qwzx"), answer([]));
    h.http.mock(api("foxe"), answer([{ entry: "foxes", explain: "n. 狐狸（复数）" }]));
    expect(await h.runAction("define", { text: "qwzx" })).toEqual({ type: "toast", message: "No definition found for “qwzx”." });
    expect(await h.runAction("define", { text: "foxe" })).toEqual({ type: "toast", message: "No definition found for “foxe”." });
});

test("reports server errors and unreachable networks as error toasts", async () => {
    const h = await harness();
    h.http.mock(api("fox"), { status: 503 });
    expect(await h.runAction("define", { text: "fox" })).toEqual({ type: "toast", message: "The dictionary answered 503.", kind: "error" });
    expect(await h.runAction("define", { text: "unmocked" })).toEqual({ type: "toast", message: "The dictionary can't be reached.", kind: "error" });
});

test("encodes the word in the URL", async () => {
    const h = await harness();
    let asked = "";
    h.http.mock(/^https:\/\/dict\.youdao\.com\//, (request) => ((asked = request.url), answer([])));
    await h.runAction("define", { text: "naïve" });
    expect(asked).toBe(api("na%C3%AFve"));
});
