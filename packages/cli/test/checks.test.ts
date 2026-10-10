import { describe, expect, test } from "bun:test";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { buildPlugin } from "../src/build.ts";
import { isNodeBuiltin, literalFetchHosts, manifestErrors, permits, usesDynamicCode } from "../src/checks.ts";
import { copyFixture } from "./build.test.ts";

describe("baron build checks", () => {
    test("manifest errors fail the build with pointers", async () => {
        const folder = copyFixture("upper");
        writeFileSync(join(folder, "manifest.json"), JSON.stringify({ id: "Bad", name: "x", description: "x", version: "1", apiVersion: 1, main: "dist/main.js", actions: [] }));
        const result = await buildPlugin(folder, { write: false });
        expect(result.ok).toBe(false);
        expect(result.errors).toEqual(expect.arrayContaining([expect.stringMatching(/^manifest\.json \/id: /), expect.stringMatching(/^manifest\.json \/version: /), expect.stringMatching(/^manifest\.json \/actions: /)]));
    });

    test("Node built-ins fail the build, naming the import", async () => {
        const folder = copyFixture("upper");
        writeFileSync(join(folder, "src/main.ts"), `import { readFileSync } from "node:fs";\nimport cp from "child_process";\nexport default { actions: { upper: () => readFileSync(String(cp)) } };\n`);
        const result = await buildPlugin(folder, { write: false });
        expect(result.ok).toBe(false);
        expect(result.errors.filter((e) => e.includes("Node built-in")).map((e) => e.split(" ")[0])).toEqual(["node:fs", "child_process"]);
    });

    test("bundles over 5 MB fail", async () => {
        const folder = copyFixture("upper");
        mkdirSync(join(folder, "src"), { recursive: true });
        writeFileSync(join(folder, "src/big.ts"), `export const big = ${JSON.stringify("x".repeat(6 * 1024 * 1024))};\n`);
        writeFileSync(join(folder, "src/main.ts"), `import { big } from "./big.ts";\nexport default { actions: { upper: () => ({ type: "copy", text: big }) } };\n`);
        const result = await buildPlugin(folder, { write: false });
        expect(result.errors.some((e) => e.includes("limit is 5 MB"))).toBe(true);
    });

    test("dynamic code and undeclared literal hosts are warnings", async () => {
        const result = await buildPlugin(copyFixture("naughty"), { write: false });
        expect(result.ok).toBe(true);
        expect(result.warnings).toEqual([
            "The bundle uses eval or new Function; declare code.dynamic in permissions so users are told at install",
            "fetch to https://evil.example isn't covered by a network: permission",
        ]);
    });
});

describe("check helpers", () => {
    test("manifestErrors is empty for a valid manifest", () => {
        expect(manifestErrors({ id: "org.example.a", name: "A", description: "D", version: "1.0.0", apiVersion: 1, main: "dist/main.js", actions: [{ id: "a", title: "A" }] })).toEqual([]);
    });

    test("recognises Node built-ins", () => {
        for (const name of ["fs", "node:fs", "fs/promises", "path", "child_process", "net", "bun:sqlite"]) expect(isNodeBuiltin(name)).toBe(true);
        for (const name of ["@baron/api", "lodash", "react"]) expect(isNodeBuiltin(name)).toBe(false);
    });

    test("finds eval and new Function but not lookalikes", () => {
        expect(usesDynamicCode("x = eval('1')")).toBe(true);
        expect(usesDynamicCode("f = new Function('a', 'return a')")).toBe(true);
        expect(usesDynamicCode("obj.eval(1); medieval(2)")).toBe(false);
    });

    test("matches network patterns like Baron", () => {
        expect(literalFetchHosts(`fetch("https://Dict.cn/a"); fetch('http://127.0.0.1:8765/'); fetch(url)`)).toEqual(["https://dict.cn", "http://127.0.0.1:8765"]);
        expect(permits(["network:dict.cn"], "https://dict.cn")).toBe(true);
        expect(permits(["network:dict.cn"], "http://dict.cn")).toBe(false);
        expect(permits(["network:*.youdao.com"], "https://dict.youdao.com")).toBe(true);
        expect(permits(["network:*.youdao.com"], "https://youdao.com")).toBe(false);
        expect(permits(["network:127.0.0.1:8765"], "http://127.0.0.1:8765")).toBe(true);
        expect(permits(["network:api.example.com:8443"], "https://api.example.com")).toBe(false);
    });
});
