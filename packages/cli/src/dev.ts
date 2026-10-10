/**
 * `baron dev`: builds the plugin, registers its folder with Baron over developer mode's socket, rebuilds and
 * reloads on every save, and prints the plugin's logs and errors with TypeScript positions.
 */
import { watch } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { buildPlugin } from "./build.ts";
import { SourceMap } from "./sourcemap.ts";

export const defaultSocket = join(homedir(), "Library", "Application Support", "Baron", "dev.sock");

export interface DevOptions {
    socket?: string;
    log?: (line: string) => void;
    /** Stop after this many rebuilds (tests); runs until interrupted otherwise. */
    rebuilds?: number;
    signal?: AbortSignal;
}

export async function devPlugin(directory: string, options: DevOptions = {}): Promise<number> {
    const folder = resolve(directory);
    const log = options.log ?? console.log;
    let built = await buildPlugin(folder);
    if (!built.ok) {
        for (const error of built.errors) log(`error: ${error}`);
        return 1;
    }
    let map = built.code ? SourceMap.fromBundle(built.code) : undefined;

    let buffer = "";
    const waiting: Array<(message: Record<string, unknown>) => void> = [];
    let socket: Awaited<ReturnType<typeof Bun.connect>>;
    try {
        socket = await Bun.connect({
            unix: options.socket ?? defaultSocket,
            socket: {
                data(_socket, data) {
                    buffer += data.toString();
                    let newline: number;
                    while ((newline = buffer.indexOf("\n")) >= 0) {
                        const message = JSON.parse(buffer.slice(0, newline)) as Record<string, unknown>;
                        buffer = buffer.slice(newline + 1);
                        if (message["event"] === "log") log(`[${message["level"]}] ${message["text"]}`);
                        else if (message["event"] === "error") log(`error (${message["code"]}): ${message["message"]}${message["stack"] ? `\n${map ? map.rewrite(String(message["stack"])) : message["stack"]}` : ""}`);
                        else waiting.shift()?.(message);
                    }
                },
            },
        });
    } catch {
        log("Baron isn't listening. Turn on Developer mode in Baron's Settings (General > Advanced).");
        return 1;
    }
    const request = (message: Record<string, unknown>) => new Promise<Record<string, unknown>>((resolve) => {
        waiting.push(resolve);
        socket.write(`${JSON.stringify(message)}\n`);
    });

    const registered = await request({ op: "register", folder });
    if (!registered["ok"]) {
        log(`error: ${registered["error"]}`);
        socket.end();
        return 1;
    }
    const id = String(registered["id"]);
    log(`Loaded ${id} in Baron. Watching src/ for changes…`);

    let rebuilds = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const done = Promise.withResolvers<number>();
    const watcher = watch(join(folder, "src"), { recursive: true }, () => {
        clearTimeout(timer);
        timer = setTimeout(async () => {
            const previous = built.code;
            built = await buildPlugin(folder);
            // macOS can deliver file events late (such as the folder's own creation); an unchanged bundle isn't a save.
            if (built.ok && built.code === previous) return;
            if (!built.ok) {
                for (const error of built.errors) log(`error: ${error}`);
            } else {
                map = built.code ? SourceMap.fromBundle(built.code) : undefined;
                await request({ op: "reload", id });
                log(`Rebuilt and reloaded ${id}.`);
            }
            rebuilds += 1;
            if (options.rebuilds !== undefined && rebuilds >= options.rebuilds) done.resolve(0);
        }, 150);
    });
    options.signal?.addEventListener("abort", () => done.resolve(0));
    const code = await done.promise;
    watcher.close();
    socket.end();
    return code;
}
