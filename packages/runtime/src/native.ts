/**
 * What every host (Baron's JavaScriptCore contexts, the QuickJS runner, the test harness) gives the prelude.
 * It is the only global the prelude relies on; the prelude removes it from plugin reach once installed.
 */
export interface BaronNative {
    /** Sends one JSON envelope to Baron. */
    send(json: string): void;
    /** Calls `globalThis.__baronFireTimer(id)` after `ms` milliseconds, on the plugin's queue. */
    setTimer(id: number, ms: number): void;
    clearTimer(id: number): void;
    /** Cryptographically random bytes, synchronously. */
    randomBytes(count: number): number[];
}

/** Entry points the host calls. */
export interface PreludeEntryPoints {
    __baronReceive(json: string): void;
    __baronFireTimer(id: number): void;
}
