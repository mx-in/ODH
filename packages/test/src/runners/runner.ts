/** One engine running the prelude and a plugin bundle, exchanging envelopes as JSON strings. */
export interface EngineRunner {
    readonly engine: "jsc" | "quickjs";
    /** Evaluates the prelude, then the bundle. `send` gets every envelope the plugin sends. */
    start(prelude: string, bundle: string, send: (json: string) => void): Promise<void>;
    deliver(json: string): void;
    close(): void;
}
