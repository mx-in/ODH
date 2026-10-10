import { encodeValue, isBaronError, type DispatchEnvelope, type EnvelopeError, type PluginDefinition } from "@baron/api";
import type { Channel } from "./channel.ts";
import { createHost, type Views } from "./host.ts";

/** Runs dispatches against the plugin's definition, found on `globalThis.__baronPlugin` once its bundle has run. */
export class Dispatcher {
    private readonly running = new Map<number, AbortController>();

    constructor(
        private readonly channel: Channel,
        private readonly views: Views,
        private readonly plugin: () => PluginDefinition | undefined,
    ) {}

    async dispatch(envelope: DispatchEnvelope): Promise<void> {
        const controller = new AbortController();
        this.running.set(envelope.id, controller);
        try {
            const value = await this.run(envelope, controller.signal);
            let encoded: unknown;
            try {
                encoded = encodeValue(value);
                JSON.stringify(encoded);
            } catch (error) {
                throw new Error(`The handler returned a value that can't be sent as JSON (${error instanceof Error ? error.message : String(error)})`);
            }
            this.channel.send({ v: 1, kind: "result", id: envelope.id, ok: true, value: encoded });
        } catch (error) {
            this.channel.send({ v: 1, kind: "result", id: envelope.id, ok: false, error: classify(error) });
        } finally {
            this.running.delete(envelope.id);
        }
    }

    cancel(id: number): void {
        this.running.get(id)?.abort(new Error("The dispatch was cancelled"));
    }

    get runningCount(): number {
        return this.running.size;
    }

    private async run({ target, name, payload }: DispatchEnvelope, signal: AbortSignal): Promise<unknown> {
        const plugin = this.plugin();
        if (!plugin) throw missing("The plugin defines nothing; its bundle must assign globalThis.__baronPlugin");
        const host = createHost(this.channel, this.views, { environment: payload.environment, preferences: payload.preferences, signal });
        const table = { action: plugin.actions, options: plugin.options, button: plugin.buttons, lifecycle: plugin.lifecycle }[target as "action"];
        const handler = table?.[name as keyof typeof table] as ((...args: unknown[]) => unknown) | undefined;
        if (target === "lifecycle" && handler === undefined) return undefined;
        if (typeof handler !== "function") throw missing(`The plugin has no ${target} handler named ${name}`);
        switch (target) {
            case "action":
                return await handler(payload.context, host);
            case "lifecycle":
                return name === "onUpdate" ? await handler(payload.args?.[0], host) : await handler(host);
            default:
                return await handler(payload.preferences, host);
        }
    }
}

class MissingExport extends Error {}
const missing = (message: string) => new MissingExport(message);

function classify(error: unknown): EnvelopeError {
    if (error instanceof MissingExport) return { code: "not_found", message: error.message };
    if (isBaronError(error)) return { code: error.code, message: error.message, ...(error.data ? { data: { ...error.data } } : {}) };
    if (error instanceof Error) {
        return { code: "plugin_error", message: error.message, ...(error.stack ? { stack: error.stack } : {}) };
    }
    return { code: "plugin_error", message: `The handler threw ${String(error)}` };
}
