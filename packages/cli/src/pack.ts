/** `baron pack`: builds, validates and zips the package as `<id>-<version>.baronplugin`, printing its SHA-256. */
import { existsSync, readFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { buildPlugin } from "./build.ts";

/** What a package ships when present; Baron's PackageReader.standardEntries lists the same. */
const standard = ["manifest.json", "dist", "views", "assets", "locales", "README.md", "LICENSE"];

type Named = { main: string; icon?: string; settingsPage?: string; actions?: Array<{ icon?: string }> };

/** The standard entries plus the top-level folder or file of every path the manifest names. */
export function shippedEntries(folder: string, manifest: Named): string[] {
    const named = [manifest.main, manifest.icon, manifest.settingsPage, ...(manifest.actions ?? []).map((a) => a.icon)];
    const tops = named.flatMap((path) => path?.replace(/^\.\//, "").split("/")[0] ?? []).filter((top) => top !== "..");
    return [...new Set([...standard, ...tops])].filter((entry) => existsSync(join(folder, entry)));
}

export async function packPlugin(directory: string): Promise<{ ok: boolean; file?: string; sha256?: string; errors: string[] }> {
    const folder = resolve(directory);
    const built = await buildPlugin(folder);
    if (!built.ok) return { ok: false, errors: built.errors };
    const manifest = JSON.parse(readFileSync(join(folder, "manifest.json"), "utf8")) as Named & { id: string; version: string };
    const file = join(folder, `${manifest.id}-${manifest.version}.baronplugin`);
    rmSync(file, { force: true });
    const zip = Bun.spawn(["zip", "-qrX", file, ...shippedEntries(folder, manifest)], { cwd: folder, stderr: "pipe" });
    if ((await zip.exited) !== 0) return { ok: false, errors: [`zip failed: ${await new Response(zip.stderr).text()}`] };
    const sha256 = new Bun.CryptoHasher("sha256").update(readFileSync(file)).digest("hex");
    return { ok: true, file, sha256, errors: [] };
}
