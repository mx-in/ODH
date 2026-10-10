import type { EngineRunner } from "./runner.ts";

/** Placeholder until the QuickJS-NG runner lands; see the next sub-task. */
export class QuickJSRunner implements EngineRunner {
    readonly engine = "quickjs";
    async start(): Promise<void> {
        throw new Error("The QuickJS-NG runner isn't available yet");
    }
    deliver(): void {}
    close(): void {}
}
