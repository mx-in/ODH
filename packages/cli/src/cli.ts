import { resolve } from "node:path";
import { buildPlugin } from "./build.ts";
import { manifestErrors } from "./checks.ts";
import { createPlugin, templates, type Template } from "./create.ts";
import { devPlugin } from "./dev.ts";
import { packPlugin } from "./pack.ts";
import { existsSync, readFileSync } from "node:fs";
import { join as joinPath } from "node:path";

export type Engine = "jsc" | "quickjs";

/** Runs the plugin's own `bun test` once per engine, with BARON_ENGINE set; returns the worst exit code. */
export async function testPlugin(directory: string, engines: Engine[], extra: string[] = [], log = console.log): Promise<number> {
    const built = await buildPlugin(directory);
    if (!built.ok) return 1;
    let worst = 0;
    for (const engine of engines) {
        log(`baron test: ${engine === "jsc" ? "JavaScriptCore" : "QuickJS-NG"}`);
        const child = Bun.spawn(["bun", "test", ...extra], {
            cwd: resolve(directory),
            env: { ...process.env, BARON_ENGINE: engine },
            stdout: "inherit",
            stderr: "inherit",
        });
        worst = Math.max(worst, await child.exited);
    }
    return worst;
}

const usage = `Usage: baron <command> [plugin folder]

Commands:
  create <name>  Make a plugin folder: --template action|lookup|settings (default action)
  build          Bundle src/main.ts into the manifest's main file
  dev            Build, load into Baron (Developer mode), rebuild and reload on every save
  test           Build, then run the plugin's tests on each engine: --engine jsc|quickjs|all (default all)
  validate       Check manifest.json
  pack           Build and zip the plugin as <id>-<version>.baronplugin, printing its SHA-256
`;

/** Runs one command; returns the exit code. */
export async function run(args: string[], log = console.log, error = console.error): Promise<number> {
    const [command, ...rest] = args;
    const templateFlag = rest.findIndex((a) => a === "--template" || a.startsWith("--template="));
    let template = "action";
    if (templateFlag >= 0) {
        template = rest[templateFlag]!.includes("=") ? rest[templateFlag]!.split("=")[1]! : rest[templateFlag + 1] ?? "";
        rest.splice(templateFlag, rest[templateFlag]!.includes("=") ? 1 : 2);
    }
    const engineFlag = rest.findIndex((a) => a === "--engine" || a.startsWith("--engine="));
    let engine = "all";
    if (engineFlag >= 0) {
        engine = rest[engineFlag]!.includes("=") ? rest[engineFlag]!.split("=")[1]! : rest[engineFlag + 1] ?? "";
        rest.splice(engineFlag, rest[engineFlag]!.includes("=") ? 1 : 2);
    }
    const directory = rest[0] && !rest[0].startsWith("-") ? rest.shift()! : ".";
    switch (command) {
        case "build": {
            const result = await buildPlugin(directory);
            for (const warning of result.warnings) error(`warning: ${warning}`);
            for (const message of result.errors) error(`error: ${message}`);
            if (result.ok) log(`built ${result.output} (${((result.code?.length ?? 0) / 1024).toFixed(1)} KB)`);
            return result.ok ? 0 : 1;
        }
        case "test": {
            const engines: Engine[] | undefined = { all: ["jsc", "quickjs"] as Engine[], jsc: ["jsc"] as Engine[], quickjs: ["quickjs"] as Engine[] }[engine];
            if (!engines) {
                error(`--engine is jsc, quickjs or all, not ${engine}`);
                return 2;
            }
            return await testPlugin(directory, engines, rest, log);
        }
        case "create": {
            if (!templates.includes(template as Template)) {
                error(`--template is ${templates.join(", ")}, not ${template}`);
                return 2;
            }
            try {
                const folder = createPlugin(directory, template as Template);
                log(`Created ${folder}\nNext: cd ${directory} && npm install && npx baron dev`);
                return 0;
            } catch (e) {
                error(`error: ${(e as Error).message}`);
                return 1;
            }
        }
        case "dev":
            return await devPlugin(directory, { log });
        case "validate": {
            const path = joinPath(directory, "manifest.json");
            if (!existsSync(path)) {
                error(`error: no manifest.json in ${directory}`);
                return 1;
            }
            const problems = manifestErrors(JSON.parse(readFileSync(path, "utf8")));
            for (const problem of problems) error(`error: manifest.json ${problem}`);
            if (!problems.length) log("manifest.json is valid");
            return problems.length ? 1 : 0;
        }
        case "pack": {
            const packed = await packPlugin(directory);
            for (const message of packed.errors) error(`error: ${message}`);
            if (packed.ok) log(`packed ${packed.file}\nsha256 ${packed.sha256}`);
            return packed.ok ? 0 : 1;
        }
        default:
            (command ? error : log)(command ? `Unknown command ${command}\n\n${usage}` : usage);
            return command ? 2 : 0;
    }
}
