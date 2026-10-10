import { describe, expect, test } from "bun:test";
import { base64ToBytes, bytesToBase64, decodeValue, encodeValue, type Envelope } from "../src/index.ts";

describe("base64", () => {
    test("matches the platform's encoding for every length", () => {
        for (let length = 0; length < 40; length++) {
            const bytes = Uint8Array.from({ length }, (_, i) => (i * 37 + length) & 255);
            const expected = Buffer.from(bytes).toString("base64");
            expect(bytesToBase64(bytes)).toBe(expected);
            expect(base64ToBytes(expected)).toEqual(bytes);
        }
    });

    test("rejects text that isn't base64", () => {
        expect(() => base64ToBytes("ab!d")).toThrow(TypeError);
    });
});

describe("value codec", () => {
    test("round-trips bytes at any depth and leaves everything else alone", () => {
        const value = { body: new Uint8Array([1, 2, 255]), list: [new Uint8Array([7]), "x", 3, null, true], nested: { a: { b: "c" } } };
        const wire = JSON.parse(JSON.stringify(encodeValue(value)));
        expect(wire.body).toEqual({ $bytes: "AQL/" });
        expect(decodeValue(wire)).toEqual(value);
    });

    test("only a lone $bytes key is bytes", () => {
        expect(decodeValue({ $bytes: "AQ==", other: 1 })).toEqual({ $bytes: "AQ==", other: 1 });
    });

    test("envelope types describe the design's messages", () => {
        const messages: Envelope[] = [
            { v: 1, kind: "call", id: 41, ns: "http", method: "fetch", args: ["https://dict.cn", {}] },
            { v: 1, kind: "result", id: 41, ok: false, error: { code: "permission_denied", message: "no", data: { permission: "network:dict.cn", requestable: true } } },
            { v: 1, kind: "dispatch", id: 7, target: "action", name: "lookup", payload: { environment: { apiVersion: 1, baronVersion: "0.1.0", pluginVersion: "1.0.0", platform: "macos", locale: "en", appearance: "light", development: false }, preferences: {} } },
            { v: 1, kind: "cancel", id: 7 },
        ];
        expect(messages).toHaveLength(4);
    });
});
