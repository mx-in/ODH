import { afterEach, expect, test } from "bun:test";
import { join } from "node:path";
import { createHarness, type Harness } from "@baron/test";

const api = "https://api.dictionaryapi.dev/api/v2/entries/en/";
const fox = [{ word: "fox", meanings: [{ partOfSpeech: "noun", definitions: [{ definition: "A red-furred wild canine." }] }] }];

let h: Harness | undefined;
afterEach(() => h?.close());
const harness = async () => (h = await createHarness({ plugin: join(import.meta.dir, "..") }));

test("shows the first definition", async () => {
    const h = await harness();
    h.http.mock(`${api}fox`, { body: JSON.stringify(fox), headers: { "content-type": "application/json" } });
    expect(await h.runAction("define", { text: " Fox " })).toEqual({ type: "toast", message: "fox (noun): A red-furred wild canine." });
    expect(h.permissions.used).toEqual(["network:api.dictionaryapi.dev"]);
});

test("says when there's no entry", async () => {
    const h = await harness();
    h.http.mock(`${api}qwzx`, { status: 404, body: "{}" });
    expect(await h.runAction("define", { text: "qwzx" })).toEqual({ type: "toast", message: "No definition found for “qwzx”." });
});

test("reports server errors and unreachable networks as error toasts", async () => {
    const h = await harness();
    h.http.mock(`${api}fox`, { status: 503 });
    expect(await h.runAction("define", { text: "fox" })).toEqual({ type: "toast", message: "The dictionary answered 503.", kind: "error" });
    expect(await h.runAction("define", { text: "unmocked" })).toEqual({ type: "toast", message: "The dictionary can't be reached.", kind: "error" });
});

test("encodes the word in the URL", async () => {
    const h = await harness();
    let asked = "";
    h.http.mock(/^https:\/\/api\.dictionaryapi\.dev\//, (request) => ((asked = request.url), { status: 404 }));
    await h.runAction("define", { text: "naïve" });
    expect(asked).toBe(`${api}na%C3%AFve`);
});
