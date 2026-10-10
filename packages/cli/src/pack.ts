/** `baron pack`: builds, validates and zips the package as `<id>-<version>.baronplugin`, printing its SHA-256. */
import { existsSync, readFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { buildPlugin } from "./build.ts";

/** What a package ships: the manifest and these folders and files when present. */
const shipped = ["manifest.json", "dist", "views", "assets", "locales", "README.md", "LICENSE"];

export async function packPlugin(directory: string): Promise<{ ok: boolean; file?: string; sha256?: string; errors: string[] }> {
    const folder = resolve(directory);
    const built = await buildPlugin(folder);
    if (!built.ok) return { ok: false, errors: built.errors };
    const manifest = JSON.parse(readFileSync(join(folder, "manifest.json"), "utf8")) as { id: string; version: string };
    const file = join(folder, `${manifest.id}-${manifest.version}.baronplugin`);
    rmSync(file, { force: true });
    const zip = Bun.spawn(["zip", "-qrX", file, ...shipped.filter((p) => existsSync(join(folder, p)))], { cwd: folder, stderr: "pipe" });
    if ((await zip.exited) !== 0) return { ok: false, errors: [`zip failed: ${await new Response(zip.stderr).text()}`] };
    const sha256 = new Bun.CryptoHasher("sha256").update(readFileSync(file)).digest("hex");
    return { ok: true, file, sha256, errors: [] };
}
