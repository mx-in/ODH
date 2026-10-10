import { describe, expect, test } from "bun:test";
import * as poly from "../src/polyfills/encoding.ts";

const samples = ["", "fox", "naïve café", "狐狸", "🦊 emoji", "a\u0000b", "￿"];

describe("TextEncoder and TextDecoder", () => {
    test("match the platform for valid text", () => {
        for (const text of samples) {
            expect(poly.TextEncoder.prototype.encode.call(new poly.TextEncoder(), text)).toEqual(new globalThis.TextEncoder().encode(text));
            expect(new poly.TextDecoder().decode(new globalThis.TextEncoder().encode(text))).toBe(text);
        }
    });

    test("replace lone surrogates and invalid bytes like the platform", () => {
        expect(new poly.TextEncoder().encode("\ud800x")).toEqual(new globalThis.TextEncoder().encode("\ud800x"));
        for (const bytes of [[0xff], [0xc0, 0x80], [0xe2, 0x82], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0x61, 0xe2, 0x28, 0xa1]]) {
            const input = new Uint8Array(bytes);
            expect(new poly.TextDecoder().decode(input)).toBe(new globalThis.TextDecoder().decode(input));
        }
    });

    test("agree with the platform on random bytes", () => {
        let seed = 42;
        const next = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) & 255;
        for (let round = 0; round < 500; round++) {
            const input = Uint8Array.from({ length: next() % 12 }, () => (next() % 3 === 0 ? 0x80 | (next() & 0x3f) : next()));
            expect(new poly.TextDecoder().decode(input)).toBe(new globalThis.TextDecoder().decode(input));
        }
    });

    test("fatal mode throws; the BOM is dropped unless asked", () => {
        expect(() => new poly.TextDecoder("utf-8", { fatal: true }).decode(new Uint8Array([0xff]))).toThrow(TypeError);
        expect(new poly.TextDecoder().decode(new Uint8Array([0xef, 0xbb, 0xbf, 0x61]))).toBe("a");
        expect(new poly.TextDecoder("utf8", { ignoreBOM: true }).decode(new Uint8Array([0xef, 0xbb, 0xbf, 0x61]))).toBe("﻿a");
        expect(() => new poly.TextDecoder("latin1")).toThrow(RangeError);
    });

    test("encodeInto stops before splitting a character", () => {
        const target = new Uint8Array(5);
        expect(new poly.TextEncoder().encodeInto("a狐狸", target)).toEqual({ read: 2, written: 4 });
    });
});

describe("atob and btoa", () => {
    test("match the platform", () => {
        for (const text of ["", "a", "ab", "abc", "ÿ\u0000x"]) {
            expect(poly.btoa(text)).toBe(globalThis.btoa(text));
            expect(poly.atob(globalThis.btoa(text))).toBe(text);
        }
    });

    test("throw InvalidCharacterError", () => {
        expect(() => poly.btoa("狐")).toThrow(expect.objectContaining({ name: "InvalidCharacterError" }));
        expect(() => poly.atob("a*b")).toThrow(expect.objectContaining({ name: "InvalidCharacterError" }));
    });
});

describe("structuredClone", () => {
    test("copies nested values and keeps cycles", () => {
        const source: any = { date: new Date(5), re: /x/gi, map: new Map([["k", [1]]]), set: new Set([1]), bytes: new Uint8Array([1, 2]), list: [{ a: 1 }] };
        source.self = source;
        const copy = poly.structuredClone(source);
        expect(copy).not.toBe(source);
        expect(copy.self).toBe(copy);
        expect(copy.date.getTime()).toBe(5);
        expect(copy.re.flags).toBe("gi");
        expect(copy.map.get("k")).toEqual([1]);
        expect(copy.bytes).toEqual(new Uint8Array([1, 2]));
        copy.list[0].a = 2;
        expect(source.list[0].a).toBe(1);
    });

    test("refuses functions and class instances", () => {
        expect(() => poly.structuredClone({ f() {} })).toThrow(expect.objectContaining({ name: "DataCloneError" }));
        expect(() => poly.structuredClone(new (class Thing {})())).toThrow(expect.objectContaining({ name: "DataCloneError" }));
    });
});
