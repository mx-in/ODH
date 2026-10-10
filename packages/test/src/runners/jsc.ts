import vm from "node:vm";
import type { EngineRunner } from "./runner.ts";

/**
 * JavaScriptCore, as Bun embeds it: a fresh `node:vm` context with nothing but the language built-ins,
 * so Bun's own globals can't leak into the plugin. The native side mirrors Baron's.
 */
export class JSCRunner implements EngineRunner {
    readonly engine = "jsc";
    private context?: vm.Context;
    private readonly timers = new Map<number, ReturnType<typeof setTimeout>>();
    private closed = false;

    async start(prelude: string, bundle: string, send: (json: string) => void): Promise<void> {
        const context = vm.createContext({});
        delete (context as Record<string, unknown>)["console"];
        const fire = (id: number) => {
            this.timers.delete(id);
            if (!this.closed) (vm.runInContext("__baronFireTimer", context) as (id: number) => void)(id);
        };
        context["__baronNative"] = {
            send: (json: string) => send(json),
            setTimer: (id: number, ms: number) => {
                clearTimeout(this.timers.get(id));
                this.timers.set(id, setTimeout(() => fire(id), ms));
            },
            clearTimer: (id: number) => {
                clearTimeout(this.timers.get(id));
                this.timers.delete(id);
            },
            randomBytes: (count: number) => Array.from(crypto.getRandomValues(new Uint8Array(Math.min(count, 65536)))),
            digest: (algorithm: string, base64: string) =>
                new Bun.CryptoHasher(algorithm.replace("-", "").toLowerCase() as "sha256").update(Buffer.from(base64, "base64")).digest("base64"),
        };
        vm.runInContext(prelude, context, { filename: "baron-prelude.js" });
        vm.runInContext(bundle, context, { filename: "dist/main.js" });
        this.context = context;
    }

    deliver(json: string): void {
        if (this.closed || !this.context) return;
        (vm.runInContext("__baronReceive", this.context) as (json: string) => void)(json);
    }

    close(): void {
        this.closed = true;
        for (const timer of this.timers.values()) clearTimeout(timer);
        this.timers.clear();
    }
}
