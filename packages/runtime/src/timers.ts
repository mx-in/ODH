import type { BaronNative } from "./native.ts";

type Timer = { callback: (...args: unknown[]) => void; args: unknown[]; repeat: number | undefined };

/** setTimeout and friends, backed by native one-shot timers that call `fire(id)`. */
export class Timers {
    private nextID = 1;
    private readonly timers = new Map<number, Timer>();

    constructor(private readonly native: BaronNative, private readonly report: (error: unknown) => void) {}

    set(callback: unknown, delay: unknown, args: unknown[], repeat: boolean): number {
        if (typeof callback !== "function") throw new TypeError("The timer callback must be a function");
        const id = this.nextID++;
        const ms = Math.max(0, Number(delay) || 0);
        this.timers.set(id, { callback: callback as Timer["callback"], args, repeat: repeat ? ms : undefined });
        this.native.setTimer(id, ms);
        return id;
    }

    clear(id: unknown): void {
        const key = Number(id);
        if (this.timers.delete(key)) this.native.clearTimer(key);
    }

    fire(id: number): void {
        const timer = this.timers.get(id);
        if (!timer) return;
        if (timer.repeat === undefined) this.timers.delete(id);
        else this.native.setTimer(id, timer.repeat);
        try {
            timer.callback(...timer.args);
        } catch (error) {
            this.report(error);
        }
    }

    get activeCount(): number {
        return this.timers.size;
    }

    install(target: Record<string, unknown>): void {
        target["setTimeout"] = (callback: unknown, delay?: unknown, ...args: unknown[]) => this.set(callback, delay, args, false);
        target["setInterval"] = (callback: unknown, delay?: unknown, ...args: unknown[]) => this.set(callback, delay, args, true);
        target["clearTimeout"] = (id: unknown) => this.clear(id);
        target["clearInterval"] = (id: unknown) => this.clear(id);
        target["queueMicrotask"] = (callback: unknown) => {
            if (typeof callback !== "function") throw new TypeError("queueMicrotask needs a function");
            Promise.resolve().then(() => callback()).catch(this.report);
        };
    }
}
