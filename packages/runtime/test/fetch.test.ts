import { describe, expect, test } from "bun:test";
import { Channel } from "../src/channel.ts";
import { AbortController } from "../src/polyfills/abort.ts";
import { createFetch, Headers, Request, Response } from "../src/polyfills/fetch.ts";
import { URLSearchParams } from "../src/polyfills/url.ts";

function setup() {
    const sent: any[] = [];
    const channel = new Channel({ send: (json) => sent.push(JSON.parse(json)), setTimer() {}, clearTimer() {}, randomBytes: () => [] });
    const reply = (value: unknown) => channel.receive(JSON.stringify({ v: 1, kind: "result", id: sent.at(-1).id, ok: true, value }));
    return { fetch: createFetch(channel), sent, reply };
}

describe("fetch", () => {
    test("sends one http.fetch call and builds a Response", async () => {
        const { fetch, sent, reply } = setup();
        const pending = fetch("https://dict.example/fox", { method: "post", headers: { "X-Test": "1" }, body: new URLSearchParams({ q: "fox" }) });
        await Promise.resolve();
        expect(sent[0]).toMatchObject({ ns: "http", method: "fetch" });
        const [url, init] = sent[0].args;
        expect(url).toBe("https://dict.example/fox");
        expect(init).toMatchObject({ method: "POST", responseType: "bytes", headers: { "x-test": "1", "content-type": "application/x-www-form-urlencoded;charset=UTF-8" } });
        expect(init.body).toEqual({ $bytes: "cT1mb3g=" });
        reply({ status: 201, url: "https://dict.example/fox/1", headers: { "content-type": "application/json" }, body: { $bytes: btoa('{"a":"狐"}'.replace(/狐/, "\\u72d0")) } });
        const response = await pending;
        expect([response.status, response.ok, response.redirected, response.headers.get("Content-Type")]).toEqual([201, true, true, "application/json"]);
        expect(await response.json()).toEqual({ a: "狐" });
        await expect(response.text()).rejects.toThrow("already been read");
    });

    test("non-2xx answers are responses, not errors", async () => {
        const { fetch, reply } = setup();
        const pending = fetch("https://dict.example/none");
        await Promise.resolve();
        reply({ status: 404, url: "https://dict.example/none", headers: {}, body: { $bytes: "" } });
        const response = await pending;
        expect([response.status, response.ok]).toEqual([404, false]);
    });

    test("aborting rejects at once and asks Baron to cancel", async () => {
        const { fetch, sent } = setup();
        const controller = new AbortController();
        const pending = fetch("https://slow.example", { signal: controller.signal as never });
        await Promise.resolve();
        controller.abort();
        await expect(pending).rejects.toMatchObject({ name: "AbortError" });
        expect(sent.at(-1)).toMatchObject({ ns: "http", method: "cancel", args: [sent[0].args[1].requestID] });
    });

    test("rejects host errors and bad requests", async () => {
        const { fetch } = setup();
        await expect(fetch("not a url")).rejects.toThrow(TypeError);
        await expect(fetch("https://x.example", { body: "x" })).rejects.toThrow("can't have a body");
    });
});

describe("Headers, Request and Response", () => {
    test("headers are case-insensitive and combine repeats", () => {
        const headers = new Headers([["Accept", "a"], ["accept", "b"]]);
        expect(headers.get("ACCEPT")).toBe("a, b");
        expect([...headers]).toEqual([["accept", "a, b"]]);
        expect(() => headers.set("bad name", "x")).toThrow(TypeError);
    });

    test("bodies can be read as bytes, text, JSON or an ArrayBuffer", async () => {
        expect(await Response.json({ a: 1 }).json()).toEqual({ a: 1 });
        expect(new Uint8Array(await new Response("hi").arrayBuffer())).toEqual(new Uint8Array([104, 105]));
        const request = new Request("https://x.example/a", { method: "PUT", body: "hi" });
        expect([request.method, await request.clone().text(), request.headers.get("content-type")]).toEqual(["PUT", "hi", "text/plain;charset=UTF-8"]);
    });
});
