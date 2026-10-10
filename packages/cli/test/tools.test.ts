import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { buildPlugin } from "../src/build.ts";
import { run } from "../src/cli.ts";
import { createPlugin } from "../src/create.ts";
import { devPlugin } from "../src/dev.ts";
import { shippedEntries } from "../src/pack.ts";
import { SourceMap } from "../src/sourcemap.ts";
import { copyFixture } from "./build.test.ts";

const scratch = () => {
    const folder = join(import.meta.dir, "..", ".tmp", `create-${Date.now()}-${Math.random().toString(36).slice(2)}`);
    return folder;
};

describe("source maps", () => {
    test("rewrite bundle positions in a stack to TypeScript lines", async () => {
        const folder = copyFixture("upper");
        writeFileSync(join(folder, "src/shout.ts"), `export const shout = (text: string): string => {\n    // line 2\n    throw new Error("no " + text);\n};\n`);
        const { code } = await buildPlugin(folder, { write: false });
        const map = SourceMap.fromBundle(code!)!;
        const line = code!.split("\n").findIndex((l) => l.includes('throw new Error("no "')) + 1;
        const column = code!.split("\n")[line - 1]!.indexOf("throw") + 1;
        expect(map.rewrite(`shout@dist/main.js:${line}:${column}`)).toMatch(/src\/shout\.ts:3:\d+$/);
    });
});

describe("baron create", () => {
    for (const template of ["action", "lookup", "settings"] as const) {
        test(`the ${template} template builds and passes its tests`, async () => {
            const parent = scratch();
            const folder = createPlugin("my-plugin", template, parent);
            for (const file of ["manifest.json", "src/main.ts", "test/main.test.ts", "package.json", "tsconfig.json"]) expect(existsSync(join(folder, file))).toBe(true);
            expect((await buildPlugin(folder, { write: true })).errors).toEqual([]);
            expect(await run(["test", folder, "--engine", "jsc"], () => {})).toBe(0);
            rmSync(parent, { recursive: true, force: true });
        }, 30_000);
    }

    test("refuses bad names and unknown templates", async () => {
        expect(() => createPlugin("My Plugin", "action", scratch())).toThrow("lowercase");
        expect(await run(["create", "x", "--template", "nope"], () => {}, () => {})).toBe(2);
    });
});

describe("baron validate and pack", () => {
    test("validate reports manifest problems", async () => {
        const folder = copyFixture("upper");
        const lines: string[] = [];
        expect(await run(["validate", folder], (l) => lines.push(l), (l) => lines.push(l))).toBe(0);
        writeFileSync(join(folder, "manifest.json"), JSON.stringify({ id: "Bad" }));
        expect(await run(["validate", folder], () => {}, (l) => lines.push(l))).toBe(1);
        expect(lines.some((l) => l.includes("/id"))).toBe(true);
    });

    test("pack zips what the package ships and prints its SHA-256", async () => {
        const folder = copyFixture("upper");
        const lines: string[] = [];
        expect(await run(["pack", folder], (l) => lines.push(l))).toBe(0);
        const file = join(folder, "org.example.fixture-upper-1.0.0.baronplugin");
        expect(existsSync(file)).toBe(true);
        expect(lines.join("\n")).toMatch(/sha256 [0-9a-f]{64}/);
        const listing = Bun.spawnSync(["unzip", "-Z1", file]).stdout.toString().split("\n").filter(Boolean).sort();
        expect(listing).toEqual(["dist/", "dist/main.js", "manifest.json"]);
    });

    test("ships the folders the manifest names, and nothing else", async () => {
        const folder = copyFixture("upper");
        expect((await buildPlugin(folder)).ok).toBe(true);
        mkdirSync(join(folder, "icons"));
        writeFileSync(join(folder, "icons", "a.svg"), "<svg/>");
        mkdirSync(join(folder, "src"), { recursive: true });
        const manifest = { main: "dist/main.js", icon: "./icons/a.svg", actions: [{ icon: "../outside.svg" }] };
        expect(shippedEntries(folder, manifest)).toEqual(["manifest.json", "dist", "icons"]);
    });
});

describe("baron dev", () => {
    test("registers, rebuilds and reloads on save, and prints mapped errors", async () => {
        const folder = copyFixture("upper");
        const socket = join(mkdtempSync(join(tmpdir(), "baron-dev-")), "dev.sock");
        const received: Array<Record<string, unknown>> = [];
        const server = Bun.listen({
            unix: socket,
            socket: {
                data(client, data) {
                    for (const line of data.toString().split("\n").filter(Boolean)) {
                        const message = JSON.parse(line) as Record<string, unknown>;
                        received.push(message);
                        if (message["op"] === "register") {
                            client.write(`${JSON.stringify({ ok: true, id: "org.example.fixture-upper" })}\n`);
                            client.write(`${JSON.stringify({ event: "log", id: "org.example.fixture-upper", level: "info", text: "hello from the plugin" })}\n`);
                        } else {
                            client.write(`${JSON.stringify({ ok: true })}\n`);
                        }
                    }
                },
            },
        });
        const lines: string[] = [];
        const running = devPlugin(folder, { socket, log: (l) => lines.push(l), rebuilds: 1 });
        await new Promise((r) => setTimeout(r, 400));
        writeFileSync(join(folder, "src/shout.ts"), `export const shout = (text: string): string => text.toUpperCase() + "!";\n`);
        expect(await running).toBe(0);
        server.stop(true);
        expect(received.map((m) => m["op"])).toEqual(["register", "reload"]);
        expect(received[0]!["folder"]).toBe(folder);
        expect(lines).toContain("[info] hello from the plugin");
        expect(lines.some((l) => l.startsWith("Rebuilt and reloaded"))).toBe(true);
        expect(readFileSync(join(folder, "dist/main.js"), "utf8")).toContain('"!"');
    }, 15_000);

    test("explains when Baron isn't listening", async () => {
        const lines: string[] = [];
        expect(await devPlugin(copyFixture("upper"), { socket: "/tmp/baron-nobody.sock", log: (l) => lines.push(l) })).toBe(1);
        expect(lines[0]).toContain("Developer mode");
    });
});
