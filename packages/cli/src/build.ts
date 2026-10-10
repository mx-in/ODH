/**
 * `baron build`: bundles a plugin's `src/main.ts` into one classic script (`main` in its manifest) that
 * assigns the default export to `globalThis.__baronPlugin`, with an inline source map.
 * Design: docs/design/plugin-platform/09-developer-tooling.md
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { isNodeBuiltin, literalFetchHosts, manifestErrors, maximumBundleBytes, permits, usesDynamicCode } from "./checks.ts";

export interface BuildResult {
    ok: boolean;
    /** Where the bundle was written. */
    output?: string;
    code?: string;
    errors: string[];
    warnings: string[];
}

export interface BuildOptions {
    /** Skip writing the bundle (for checks and tests). */
    write?: boolean;
}

const entryNamespace = "baron-entry";

export async function buildPlugin(directory: string, options: BuildOptions = {}): Promise<BuildResult> {
    const root = resolve(directory);
    const errors: string[] = [];
    const warnings: string[] = [];
    const manifestPath = join(root, "manifest.json");
    if (!existsSync(manifestPath)) return { ok: false, errors: [`No manifest.json in ${root}`], warnings };
    let manifest: { main?: string; permissions?: string[]; optionalPermissions?: string[] };
    try {
        manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    } catch (error) {
        return { ok: false, errors: [`manifest.json isn't valid JSON: ${(error as Error).message}`], warnings };
    }
    errors.push(...manifestErrors(manifest).map((e) => `manifest.json ${e}`));
    const source = ["src/main.ts", "src/main.tsx", "src/main.js"].map((p) => join(root, p)).find(existsSync);
    if (!source) return { ok: false, errors: ["No src/main.ts to build"], warnings };

    const result = await Bun.build({
        entrypoints: [`${entryNamespace}:main`],
        format: "iife",
        target: "browser",
        sourcemap: "inline",
        minify: false,
        plugins: [{
            name: "baron-entry",
            setup(build) {
                build.onResolve({ filter: /^baron-entry:main$/ }, (args) => ({ path: args.path, namespace: entryNamespace }));
                build.onResolve({ filter: /^[^./]/ }, (args) => {
                    if (!isNodeBuiltin(args.path)) return undefined;
                    errors.push(`${args.path} is a Node built-in; Baron plugins run in a sandbox without Node APIs (imported from ${args.importer})`);
                    return { path: args.path, namespace: "baron-forbidden" };
                });
                build.onLoad({ filter: /.*/, namespace: "baron-forbidden" }, () => ({ contents: "export {};", loader: "js" }));
                build.onLoad({ filter: /.*/, namespace: entryNamespace }, () => ({
                    contents: `import plugin from ${JSON.stringify(source)};\nglobalThis.__baronPlugin = plugin;\n`,
                    loader: "ts",
                    resolveDir: root,
                }));
            },
        }],
        throw: false,
    });
    for (const log of result.logs) {
        const text = log.message + (log.position ? ` (${log.position.file}:${log.position.line})` : "");
        (log.level === "error" ? errors : warnings).push(text);
    }
    if (!result.success || !result.outputs[0]) return { ok: false, errors: errors.length ? errors : ["The bundle didn't build"], warnings };

    const code = await result.outputs[0].text();
    if (code.length > maximumBundleBytes) errors.push(`The bundle is ${(code.length / 1024 / 1024).toFixed(1)} MB; the limit is 5 MB`);
    const permissions = [...(manifest.permissions ?? []), ...(manifest.optionalPermissions ?? [])];
    if (usesDynamicCode(code) && !permissions.includes("code.dynamic")) {
        warnings.push("The bundle uses eval or new Function; declare code.dynamic in permissions so users are told at install");
    }
    if (!permissions.includes("network:*")) {
        for (const origin of literalFetchHosts(code)) {
            if (!permits(permissions, origin)) warnings.push(`fetch to ${origin} isn't covered by a network: permission`);
        }
    }
    if (errors.length) return { ok: false, errors, warnings };
    const output = join(root, manifest.main ?? "dist/main.js");
    if (options.write !== false) {
        mkdirSync(dirname(output), { recursive: true });
        writeFileSync(output, code);
    }
    return { ok: true, output, code, errors, warnings };
}
