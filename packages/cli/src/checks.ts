/** What `baron build` checks besides compiling. Design: 09-developer-tooling.md#checks-in-baron-build */
import Ajv2020, { type ErrorObject } from "ajv/dist/2020.js";
import schema from "@baron/api/schema/manifest-1.json" with { type: "json" };
import { networkPermissionCovers } from "@baron/api";
import { builtinModules } from "node:module";

const validate = new Ajv2020({ allErrors: true, strict: true }).compile(schema);

export const maximumBundleBytes = 5 * 1024 * 1024;

/** Schema errors as "pointer: message", pointing at the offending or missing field. */
export function manifestErrors(manifest: unknown): string[] {
    if (validate(manifest)) return [];
    const seen = new Set<string>();
    for (const error of validate.errors ?? []) {
        if (error.keyword === "if") continue;
        seen.add(`${pointerOf(error) || "/"}: ${error.message ?? "is invalid"}`);
    }
    return [...seen];
}

function pointerOf(error: ErrorObject): string {
    const params = error.params as Record<string, unknown>;
    const field = params["missingProperty"] ?? params["additionalProperty"] ?? params["unevaluatedProperty"];
    return typeof field === "string" ? `${error.instancePath}/${field}` : error.instancePath;
}

const nodeBuiltins = new Set(builtinModules.flatMap((name) => [name, `node:${name}`]));

/** True for `fs`, `node:fs`, `fs/promises` and the like. */
export function isNodeBuiltin(specifier: string): boolean {
    return nodeBuiltins.has(specifier) || nodeBuiltins.has(specifier.split("/")[0]!) || specifier.startsWith("node:") || specifier.startsWith("bun:");
}

/** Strips the inline source map, which quotes the original sources. */
const withoutSourceMap = (code: string) => code.replace(/\/\/# sourceMappingURL=.*$/m, "");

export function usesDynamicCode(code: string): boolean {
    return /(^|[^.\w$])eval\s*\(|\bnew\s+Function\s*\(/.test(withoutSourceMap(code));
}

/** Hosts of string-literal URLs passed straight to fetch or host.http.fetch. */
export function literalFetchHosts(code: string): string[] {
    const hosts = new Set<string>();
    for (const match of withoutSourceMap(code).matchAll(/fetch\(\s*["'`](https?):\/\/([^/"'`?#:]+)(?::(\d+))?/g)) {
        hosts.add(`${match[1]}://${match[2]!.toLowerCase()}${match[3] ? `:${match[3]}` : ""}`);
    }
    return [...hosts];
}

/** Whether a `network:` permission covers the URL origin; the matcher is shared with `@baron/test`. */
export function permits(permissions: string[], origin: string): boolean {
    return permissions.some((permission) => networkPermissionCovers(permission, origin));
}
