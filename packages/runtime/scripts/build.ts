/**
 * Compiles the prelude and the page bridge into classic scripts: dist/prelude.js and dist/page-bridge.js, also
 * copied into Baron's Swift sources (macos/Sources/BaronRuntime/Resources/prelude.js and
 * macos/Sources/BaronWeb/Resources/page-bridge.js). A test fails while a copy is out of date.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const sources = join(root, "..", "..", "macos", "Sources");
export const swiftCopy = join(sources, "BaronRuntime", "Resources", "prelude.js");
export const pageBridgeCopy = join(sources, "BaronWeb", "Resources", "page-bridge.js");

async function build(entry: string, title: string): Promise<string> {
    const result = await Bun.build({
        entrypoints: [join(root, "src", entry)],
        format: "iife",
        target: "browser",
        minify: { whitespace: true, syntax: true, identifiers: false },
    });
    if (!result.success) throw new AggregateError(result.logs, `The ${title} didn't build`);
    return `// Baron ${title}, built from packages/runtime by \`npm run build -w packages/runtime\`. Do not edit.\n${await result.outputs[0]!.text()}`;
}

export const buildPrelude = () => build("index.ts", "plugin prelude");
export const buildPageBridge = () => build("page.ts", "page bridge");

if (import.meta.main) {
    mkdirSync(join(root, "dist"), { recursive: true });
    for (const [name, code, copy] of [["prelude", await buildPrelude(), swiftCopy], ["page-bridge", await buildPageBridge(), pageBridgeCopy]] as const) {
        writeFileSync(join(root, "dist", `${name}.js`), code);
        mkdirSync(join(copy, ".."), { recursive: true });
        writeFileSync(copy, code);
        console.log(`${name}: ${(code.length / 1024).toFixed(1)} KB`);
    }
}
