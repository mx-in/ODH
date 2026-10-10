/**
 * Runs a plugin's built bundle on a real engine against the mock host. Design: 09-developer-tooling.md#testing-on-both-engines
 */
import { decodeValue, encodeValue, type DispatchTarget, type EnvelopeError, type Envelope, type PluginManifest, type Preferences, type SelectionContext } from "@baron/api";
import { buildPlugin } from "@baron/cli";
import { buildPrelude } from "@baron/runtime/build";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { MockHost, type MockRoute } from "./mock-host.ts";
import { JSCRunner } from "./runners/jsc.ts";
import type { EngineRunner } from "./runners/runner.ts";

export type Engine = "jsc" | "quickjs";

export interface HarnessOptions {
    /** The plugin folder (with manifest.json and src/main.ts). Defaults to the current directory. */
    plugin?: string;
    /** Defaults to $BARON_ENGINE, else jsc. */
    engine?: Engine | string | undefined;
    /** Overrides the manifest's defaults. */
    preferences?: Preferences;
    locale?: string;
}

/** A dispatch that failed: the plugin threw, or a host call it didn't catch failed. */
export class DispatchError extends Error {
    constructor(readonly code: EnvelopeError["code"], message: string, readonly data?: Record<string, unknown>) {
        super(message);
        this.name = "DispatchError";
    }
}

let prelude: Promise<string> | undefined;

export async function createHarness(options: HarnessOptions = {}) {
    const folder = resolve(options.plugin ?? ".");
    const manifest = JSON.parse(readFileSync(join(folder, "manifest.json"), "utf8")) as PluginManifest;
    const built = await buildPlugin(folder, { write: false });
    if (!built.ok) throw new Error(`The plugin doesn't build:\n${built.errors.join("\n")}`);
    prelude ??= buildPrelude();

    const engine = (options.engine ?? process.env["BARON_ENGINE"] ?? "jsc") as Engine;
    const runner: EngineRunner = engine === "quickjs" ? new (await import("./runners/quickjs.ts")).QuickJSRunner() : new JSCRunner();
    const host = new MockHost(manifest);
    const waiting = new Map<number, { resolve(value: unknown): void; reject(error: unknown): void }>();
    let nextID = 1;

    const preferences: Preferences = { ...defaults(manifest), ...options.preferences };
    const environment = { apiVersion: 1 as const, baronVersion: "0.1.0", pluginVersion: manifest.version, platform: "macos" as const,
                          locale: options.locale ?? "en", appearance: "light" as const, development: true };

    await runner.start(await prelude, built.code!, (json) => {
        const envelope = JSON.parse(json) as Envelope;
        if (envelope.kind === "call") {
            void host.handle(envelope).then((result) => runner.deliver(JSON.stringify(result)));
        } else if (envelope.kind === "result") {
            const pending = waiting.get(envelope.id);
            waiting.delete(envelope.id);
            if (envelope.ok) pending?.resolve(decodeValue(envelope.value));
            else pending?.reject(new DispatchError(envelope.error.code, envelope.error.message, envelope.error.data));
        }
    });

    const dispatch = (target: DispatchTarget, name: string, extra: { context?: SelectionContext; args?: unknown[]; preferences?: Preferences }) =>
        new Promise<unknown>((resolve, reject) => {
            const id = nextID++;
            waiting.set(id, { resolve, reject });
            runner.deliver(JSON.stringify({
                v: 1, kind: "dispatch", id, target, name,
                payload: encodeValue({ environment, preferences: { ...preferences, ...extra.preferences }, ...(extra.context ? { context: extra.context } : {}), ...(extra.args ? { args: extra.args } : {}) }),
            }));
        });

    return {
        engine,
        manifest,
        host,
        http: { mock: (match: string | RegExp, route: MockRoute) => host.http.mock(match, route) },
        permissions: {
            get used() { return host.permissionsUsed; },
            grant: (name: string) => void host.granted.add(name),
        },
        /** Runs an action by its manifest id with a selection; context fields default to a plain selection in TextEdit. */
        runAction(actionID: string, context: Partial<SelectionContext> & { text: string }) {
            const action = manifest.actions.find((a) => a.id === actionID);
            if (!action) throw new Error(`The manifest has no action ${actionID}`);
            const full: SelectionContext = { source: "ax-text", editable: false, app: { id: "com.apple.TextEdit", name: "TextEdit", pid: 1 }, platform: "macos", ...context };
            return dispatch("action", action.run ?? action.id, { context: full });
        },
        runOptions: (name: string, overrides: Preferences = {}) => dispatch("options", name, { preferences: overrides }),
        runButton: (name: string, overrides: Preferences = {}) => dispatch("button", name, { preferences: overrides }),
        runLifecycle: (name: "onInstall" | "onUpdate", args: unknown[] = []) => dispatch("lifecycle", name, { args }),
        close: () => runner.close(),
    };
}

export type Harness = Awaited<ReturnType<typeof createHarness>>;

function defaults(manifest: PluginManifest): Preferences {
    const values: Record<string, unknown> = {};
    for (const preference of manifest.preferences ?? []) {
        if ("default" in preference && preference.default !== undefined) values[preference.id] = preference.default;
    }
    return values as Preferences;
}
