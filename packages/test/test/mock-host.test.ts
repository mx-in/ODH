import { describe, expect, test } from "bun:test";
import { MockHost } from "../src/index.ts";

const call = (host: MockHost, ns: string, method: string, ...args: unknown[]) => host.handle({ v: 1, kind: "call", id: 1, ns, method, args });

describe("MockHost", () => {
    test("serves mocked fetches to declared hosts and records the permission used", async () => {
        const host = new MockHost({ permissions: ["network:dict.example"] });
        host.http.mock("https://dict.example/fox", { body: "a small wild dog", headers: { "Content-Type": "text/plain" } });
        const result = await call(host, "http", "fetch", "https://dict.example/fox", {});
        expect(result).toMatchObject({ ok: true, value: { status: 200, body: "a small wild dog", headers: { "content-type": "text/plain" } } });
        expect(host.permissionsUsed).toEqual(["network:dict.example"]);
    });

    test("refuses undeclared hosts, saying whether asking could help", async () => {
        const strict = new MockHost({ permissions: [] });
        expect(await call(strict, "http", "fetch", "https://evil.example/", {})).toMatchObject({ ok: false, error: { code: "permission_denied", data: { permission: "network:evil.example", requestable: false } } });
        const asking = new MockHost({ optionalPermissions: ["network:*"] });
        expect(await call(asking, "http", "fetch", "https://dict.cn/", {})).toMatchObject({ error: { data: { requestable: true } } });
        asking.allowWhenAsked = true;
        expect(await call(asking, "permissions", "request", ["network:dict.cn"])).toMatchObject({ value: ["network:dict.cn"] });
        asking.http.mock(/^https:\/\/dict\.cn\//, { body: "ok" });
        expect(await call(asking, "http", "fetch", "https://dict.cn/x", {})).toMatchObject({ ok: true });
    });

    test("route functions see the request; bytes travel as $bytes", async () => {
        const host = new MockHost({ permissions: ["network:127.0.0.1:8765"] });
        host.http.mock("http://127.0.0.1:8765", (request) => ({ body: `${request.method} ${new TextDecoder().decode(request.body)}` }));
        expect(await call(host, "http", "fetch", "http://127.0.0.1:8765", { method: "POST", body: "{}", responseType: "bytes" })).toMatchObject({ value: { body: { $bytes: btoa("POST {}") } } });
    });

    test("keeps storage, cache and secrets, with secrets behind their permission", async () => {
        const host = new MockHost({ permissions: [] });
        await call(host, "storage", "set", "history", ["fox"]);
        expect(await call(host, "storage", "get", "history")).toMatchObject({ value: ["fox"] });
        expect(await call(host, "storage", "keys")).toMatchObject({ value: ["history"] });
        expect(await call(host, "secrets", "get", "key")).toMatchObject({ ok: false, error: { code: "permission_denied" } });
    });

    test("records toasts, replacements and logs, and segments text", async () => {
        const host = new MockHost({ permissions: ["selection.replace"] });
        await call(host, "ui", "toast", "Added", "success");
        await call(host, "selection", "replace", "FOX");
        await call(host, "log", "warn", "careful");
        expect([host.toasts, host.replacements, host.logs]).toEqual([[{ message: "Added", kind: "success" }], ["FOX"], [{ level: "warn", text: "careful" }]]);
        expect(await call(host, "text", "segment", "The fox runs. It is quick.", "sentence")).toMatchObject({ value: [{ start: 0, end: 14 }, { start: 14, end: 26 }] });
        expect(await call(host, "nope", "x")).toMatchObject({ error: { code: "invalid_argument" } });
    });
});
