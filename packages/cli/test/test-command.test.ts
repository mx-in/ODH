import { expect, test } from "bun:test";
import { run } from "../src/cli.ts";
import { copyFixture } from "./build.test.ts";

test("baron test runs the plugin's tests on both engines by default, and on one when asked", async () => {
    const folder = copyFixture("upper");
    const lines: string[] = [];
    expect(await run(["test", folder], (l) => lines.push(l))).toBe(0);
    expect(lines).toEqual(["baron test: JavaScriptCore", "baron test: QuickJS-NG"]);
    const only: string[] = [];
    expect(await run(["test", folder, "--engine", "quickjs"], (l) => only.push(l))).toBe(0);
    expect(only).toEqual(["baron test: QuickJS-NG"]);
    expect(await run(["test", folder, "--engine=lua"], () => {}, () => {})).toBe(2);
}, 30_000);

test("a failing plugin test fails baron test", async () => {
    const folder = copyFixture("upper");
    await Bun.write(`${folder}/test/fails.test.ts`, `import { test, expect } from "bun:test"; test("no", () => expect(1).toBe(2));`);
    expect(await run(["test", folder, "--engine", "jsc"], () => {})).toBe(1);
}, 30_000);
