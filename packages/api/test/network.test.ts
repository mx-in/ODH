import { expect, test } from "bun:test";
import { networkPermissionCovers as covers, networkPermissionFor } from "../src/index.ts";

test("network patterns match as the design describes", () => {
    expect(covers("network:dict.cn", "https://dict.cn/fox")).toBe(true);
    expect(covers("network:dict.cn", "http://dict.cn/fox")).toBe(false);
    expect(covers("network:dict.cn", "https://dict.cn:8443/")).toBe(false);
    expect(covers("network:*.youdao.com", "https://dict.youdao.com/")).toBe(true);
    expect(covers("network:*.youdao.com", "https://youdao.com/")).toBe(false);
    expect(covers("network:api.example.com:8443", "https://api.example.com:8443/x")).toBe(true);
    expect(covers("network:http://example.com", "http://example.com/")).toBe(true);
    expect(covers("network:127.0.0.1:8765", "http://127.0.0.1:8765")).toBe(true);
    expect(covers("network:127.0.0.1:8765", "http://127.0.0.1:9000")).toBe(false);
    expect(covers("secrets", "https://dict.cn")).toBe(false);
});

test("names the permission for a URL", () => {
    expect(networkPermissionFor("https://Dict.cn/fox")).toBe("network:dict.cn");
    expect(networkPermissionFor("http://example.com/")).toBe("network:http://example.com");
    expect(networkPermissionFor("http://127.0.0.1:8765/")).toBe("network:127.0.0.1:8765");
});

import corpus from "./network-corpus.json" with { type: "json" };

test.each(corpus)("$permission vs $url: $note", ({ permission, url, covers: expected }) => {
    expect(covers(permission, url)).toBe(expected);
});
