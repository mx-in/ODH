import { buildPlugin } from "./build.ts";

const usage = `Usage: baron <command> [plugin folder]

Commands:
  build      Bundle src/main.ts into the manifest's main file
`;

/** Runs one command; returns the exit code. */
export async function run(args: string[], log = console.log, error = console.error): Promise<number> {
    const [command, directory = "."] = args;
    switch (command) {
        case "build": {
            const result = await buildPlugin(directory);
            for (const warning of result.warnings) error(`warning: ${warning}`);
            for (const message of result.errors) error(`error: ${message}`);
            if (result.ok) log(`built ${result.output} (${((result.code?.length ?? 0) / 1024).toFixed(1)} KB)`);
            return result.ok ? 0 : 1;
        }
        default:
            (command ? error : log)(command ? `Unknown command ${command}\n\n${usage}` : usage);
            return command ? 2 : 0;
    }
}
