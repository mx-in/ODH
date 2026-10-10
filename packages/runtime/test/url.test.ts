import { describe, expect, test } from "bun:test";
import { URL, URLSearchParams } from "../src/polyfills/url.ts";

describe("URL polyfill", () => {
    test("parses and normalises like browsers", () => {
        const url = new URL("HTTPS://Example.com:443/a/../b?q=fox%20es#h");
        expect(url.href).toBe("https://example.com/b?q=fox%20es#h");
        expect([url.protocol, url.host, url.pathname, url.hash]).toEqual(["https:", "example.com", "/b", "#h"]);
        expect(url.searchParams.get("q")).toBe("fox es");
    });

    test("resolves relative URLs and international domains", () => {
        expect(new URL("../c?d", "https://x.example/a/b/").href).toBe("https://x.example/a/c?d");
        expect(new URL("https://例子.测试/").hostname).toBe("xn--fsqu00a.xn--0zwm56d");
    });

    test("rejects what isn't a URL", () => {
        expect(() => new URL("not a url")).toThrow(TypeError);
    });

    test("URLSearchParams builds and edits queries", () => {
        const params = new URLSearchParams({ word: "fox es", lang: "en" });
        params.append("lang", "fr");
        expect(params.toString()).toBe("word=fox+es&lang=en&lang=fr");
        expect(params.getAll("lang")).toEqual(["en", "fr"]);
        expect([...new URLSearchParams("a=1&b=%E7%8B%90")]).toEqual([["a", "1"], ["b", "狐"]]);
    });
});
