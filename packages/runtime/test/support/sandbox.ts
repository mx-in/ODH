import vm from "node:vm";
import { buildPrelude } from "../../scripts/build.ts";

let prelude: Promise<string> | undefined;

/** A bare JavaScript context, like Baron's, running the built prelude over a scripted native side. */
export async function createSandbox() {
    prelude ??= buildPrelude();
    const sent: any[] = [];
    const timers = new Map<number, ReturnType<typeof setTimeout>>();
    const context = vm.createContext({});
    const fire = (id: number) => (vm.runInContext("__baronFireTimer", context) as (id: number) => void)(id);
    context["__baronNative"] = {
        send: (json: string) => sent.push(JSON.parse(json)),
        setTimer: (id: number, ms: number) => timers.set(id, setTimeout(() => fire(id), ms)),
        clearTimer: (id: number) => clearTimeout(timers.get(id)),
        randomBytes: (count: number) => Array.from(crypto.getRandomValues(new Uint8Array(count))),
        digest: (algorithm: string, base64: string) => new Bun.CryptoHasher(algorithm.replace("-", "").toLowerCase() as "sha256").update(Buffer.from(base64, "base64")).digest("base64"),
    };
    vm.runInContext(await prelude, context);
    const receive = vm.runInContext("__baronReceive", context) as (json: string) => void;
    return {
        context,
        sent,
        run: (code: string) => vm.runInContext(code, context),
        deliver: (envelope: unknown) => receive(JSON.stringify(envelope)),
        /** Waits until an envelope matching the predicate has been sent. */
        async waitFor(predicate: (envelope: any) => boolean, ms = 1000) {
            const end = Date.now() + ms;
            while (Date.now() < end) {
                const found = sent.find(predicate);
                if (found) return found;
                await new Promise((r) => setTimeout(r, 2));
            }
            throw new Error(`No matching envelope; sent: ${JSON.stringify(sent)}`);
        },
    };
}
