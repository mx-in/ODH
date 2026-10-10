import { describe, expect, test } from "bun:test";
import { BaronError, isBaronError } from "@baron/api";
import { Channel } from "../src/channel.ts";

function setup() {
    const sent: any[] = [];
    const channel = new Channel({ send: (json) => sent.push(JSON.parse(json)), setTimer() {}, clearTimer() {}, randomBytes: () => [] });
    return { channel, sent };
}

describe("Channel", () => {
    test("numbers calls and resolves each with its own result", async () => {
        const { channel, sent } = setup();
        const first = channel.call("storage", "get", ["a"]);
        const second = channel.call("storage", "get", ["b"]);
        expect(sent.map((e) => [e.kind, e.id, e.ns, e.method, e.args])).toEqual([["call", 1, "storage", "get", ["a"]], ["call", 2, "storage", "get", ["b"]]]);
        channel.receive(JSON.stringify({ v: 1, kind: "result", id: 2, ok: true, value: "B" }));
        channel.receive(JSON.stringify({ v: 1, kind: "result", id: 1, ok: true, value: "A" }));
        expect(await Promise.all([first, second])).toEqual(["A", "B"]);
        expect(channel.pendingCount).toBe(0);
    });

    test("rejects with a BaronError carrying the code and data", async () => {
        const { channel } = setup();
        const call = channel.call("http", "fetch", ["https://x.example"]);
        channel.receive(JSON.stringify({ v: 1, kind: "result", id: 1, ok: false, error: { code: "permission_denied", message: "no", data: { requestable: true } } }));
        const error = (await call.catch((e: unknown) => e)) as BaronError;
        expect(error).toBeInstanceOf(BaronError);
        expect(isBaronError(error, "permission_denied")).toBe(true);
        expect(error.data).toEqual({ requestable: true });
    });

    test("encodes and decodes bytes", async () => {
        const { channel, sent } = setup();
        const call = channel.call("cache", "set", [new Uint8Array([1, 2])]);
        expect(sent[0].args).toEqual([{ $bytes: "AQI=" }]);
        channel.receive(JSON.stringify({ v: 1, kind: "result", id: 1, ok: true, value: { $bytes: "/w==" } }));
        expect(await call).toEqual(new Uint8Array([255]));
    });

    test("passes other envelopes on and ignores unknown results", () => {
        const { channel } = setup();
        const seen: string[] = [];
        channel.onEnvelope = (e) => seen.push(e.kind);
        channel.receive(JSON.stringify({ v: 1, kind: "result", id: 99, ok: true }));
        channel.receive(JSON.stringify({ v: 1, kind: "cancel", id: 3 }));
        expect(seen).toEqual(["cancel"]);
    });
});
