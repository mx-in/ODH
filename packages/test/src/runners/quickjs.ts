import { existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { Subprocess } from "bun";
import type { EngineRunner } from "./runner.ts";

/** Finds qjs: $BARON_QJS, or .tools/qjs in this folder or one above it (see scripts/fetch-qjs.sh). */
export function findQJS(start = process.cwd()): string {
    if (process.env["BARON_QJS"]) return process.env["BARON_QJS"];
    for (let folder = start; ; folder = dirname(folder)) {
        const candidate = join(folder, ".tools", "qjs");
        if (existsSync(candidate)) return candidate;
        if (dirname(folder) === folder) break;
    }
    throw new Error("QuickJS-NG's qjs wasn't found; run `npm run tools:qjs` at the repository root, or set BARON_QJS");
}

/** QuickJS-NG in a child process, driven by qjs-driver.js over JSON lines. */
export class QuickJSRunner implements EngineRunner {
    readonly engine = "quickjs";
    private process?: Subprocess<"pipe", "pipe", "pipe">;

    async start(prelude: string, bundle: string, send: (json: string) => void): Promise<void> {
        const folder = mkdtempSync(join(tmpdir(), "baron-qjs-"));
        writeFileSync(join(folder, "prelude.js"), prelude);
        writeFileSync(join(folder, "bundle.js"), bundle);
        const child = Bun.spawn([findQJS(import.meta.dir), "--std", "--script", join(import.meta.dir, "qjs-driver.js"), join(folder, "prelude.js"), join(folder, "bundle.js")],
                                { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
        this.process = child;
        void (async () => {
            let buffered = "";
            const decoder = new TextDecoder();
            for await (const chunk of child.stdout) {
                buffered += decoder.decode(chunk, { stream: true });
                let newline: number;
                while ((newline = buffered.indexOf("\n")) >= 0) {
                    const line = buffered.slice(0, newline);
                    buffered = buffered.slice(newline + 1);
                    if (line.trim()) send(line);
                }
            }
        })();
        void (async () => {
            const text = await new Response(child.stderr).text();
            if (text.trim()) console.error(`qjs: ${text.trim()}`);
        })();
    }

    deliver(json: string): void {
        this.process?.stdin.write(`${json}\n`);
        void this.process?.stdin.flush();
    }

    close(): void {
        void this.process?.stdin.end();
        this.process?.kill();
    }
}
