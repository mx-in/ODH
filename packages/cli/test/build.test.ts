import { describe, expect, test } from "bun:test";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import vm from "node:vm";
import { buildPlugin } from "../src/build.ts";
import { run } from "../src/cli.ts";

/** Copies a fixture inside the package (gitignored .tmp/) so it resolves @baron/api from the workspace. */
export function copyFixture(name: string): string {
    const scratch = join(import.meta.dir, "..", ".tmp");
    mkdirSync(scratch, { recursive: true });
    const folder = mkdtempSync(join(scratch, `${name}-`));
    cpSync(join(import.meta.dir, "fixtures", name), folder, { recursive: true });
    return folder;
}

describe("baron build", () => {
    test("bundles src/main.ts and its imports into one classic script defining __baronPlugin", async () => {
        const folder = copyFixture("upper");
        const result = await buildPlugin(folder);
        expect(result.errors).toEqual([]);
        expect(result.output).toBe(join(folder, "dist/main.js"));
        const code = readFileSync(join(folder, "dist/main.js"), "utf8");
        expect(code).not.toMatch(/^\s*(import|export)\s/m);
        const context = vm.createContext({});
        vm.runInContext(code, context);
        expect(vm.runInContext(`__baronPlugin.actions.upper({ text: "fox" })`, context)).toEqual({ type: "replace", text: "FOX" });
    });

    test("embeds a source map pointing at the TypeScript", async () => {
        const result = await buildPlugin(copyFixture("upper"), { write: false });
        const map = result.code!.match(/sourceMappingURL=data:application\/json;base64,([A-Za-z0-9+/=]+)/)?.[1];
        expect(map).toBeDefined();
        const sources: string[] = JSON.parse(Buffer.from(map!, "base64").toString()).sources;
        expect(sources.some((s) => s.endsWith("shout.ts"))).toBe(true);
    });

    test("reports a missing manifest or entry", async () => {
        expect((await buildPlugin(tmpdir() + "/baron-none-" + Date.now())).errors[0]).toContain("No manifest.json");
    });

    test("the CLI prints what it built and returns an exit code", async () => {
        const folder = copyFixture("upper");
        const lines: string[] = [];
        expect(await run(["build", folder], (l) => lines.push(l), (l) => lines.push(l))).toBe(0);
        expect(lines[0]).toMatch(/^built .*dist\/main\.js \(\d+\.\d KB\)$/);
        expect(existsSync(join(folder, "dist/main.js"))).toBe(true);
        expect(await run(["frobnicate"], () => {}, () => {})).toBe(2);
    });
});
