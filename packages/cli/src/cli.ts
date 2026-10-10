import { resolve } from "node:path";
import { buildPlugin } from "./build.ts";

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
  build      Bundle src/main.ts into the manifest's main file
  test       Build, then run the plugin's tests on each engine
             --engine jsc|quickjs|all (default all)
`;

/** Runs one command; returns the exit code. */
export async function run(args: string[], log = console.log, error = console.error): Promise<number> {
    const [command, ...rest] = args;
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
        default:
            (command ? error : log)(command ? `Unknown command ${command}\n\n${usage}` : usage);
            return command ? 2 : 0;
    }
}
