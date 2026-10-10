/**
 * Compiles the prelude into one classic script: dist/prelude.js, also copied into Baron's Swift runtime
 * (macos/Sources/BaronRuntime/Resources/prelude.js). A test fails while the copy is out of date.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
export const swiftCopy = join(root, "..", "..", "macos", "Sources", "BaronRuntime", "Resources", "prelude.js");

export async function buildPrelude(): Promise<string> {
    const result = await Bun.build({
        entrypoints: [join(root, "src", "index.ts")],
        format: "iife",
        target: "browser",
        minify: { whitespace: true, syntax: true, identifiers: false },
    });
    if (!result.success) throw new AggregateError(result.logs, "The prelude didn't build");
    return `// Baron plugin prelude, built from packages/runtime by \`npm run build -w packages/runtime\`. Do not edit.\n${await result.outputs[0]!.text()}`;
}

if (import.meta.main) {
    const code = await buildPrelude();
    mkdirSync(join(root, "dist"), { recursive: true });
    writeFileSync(join(root, "dist", "prelude.js"), code);
    writeFileSync(swiftCopy, code);
    console.log(`prelude: ${(code.length / 1024).toFixed(1)} KB`);
}
