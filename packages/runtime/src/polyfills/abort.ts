/** Just enough of DOM events for AbortSignal, plus DOMException for the errors fetch and abort throw. */

export class DOMException extends Error {
    constructor(message = "", name = "Error") {
        super(message);
        Object.defineProperty(this, "name", { value: name, enumerable: false, configurable: true });
    }
}

export class Event {
    readonly type: string;
    target: EventTarget | null = null;
    defaultPrevented = false;
    constructor(type: string) {
        this.type = String(type);
    }
    preventDefault(): void {
        this.defaultPrevented = true;
    }
}

type Listener = { callback: (event: Event) => void; once: boolean };

export class EventTarget {
    private readonly listeners = new Map<string, Listener[]>();

    addEventListener(type: string, callback: ((event: Event) => void) | { handleEvent(event: Event): void } | null, options?: boolean | { once?: boolean; signal?: AbortSignal }): void {
        if (!callback) return;
        const fn = typeof callback === "function" ? callback : (event: Event) => callback.handleEvent(event);
        const once = typeof options === "object" && Boolean(options.once);
        const signal = typeof options === "object" ? options.signal : undefined;
        if (signal?.aborted) return;
        const list = this.listeners.get(type) ?? [];
        if (list.some((l) => l.callback === fn)) return;
        list.push({ callback: fn, once });
        this.listeners.set(type, list);
        signal?.addEventListener("abort", () => this.removeEventListener(type, fn), { once: true });
    }

    removeEventListener(type: string, callback: ((event: Event) => void) | null): void {
        const list = this.listeners.get(type);
        if (list) this.listeners.set(type, list.filter((l) => l.callback !== callback));
    }

    dispatchEvent(event: Event): boolean {
        event.target = this;
        const handler = (this as unknown as Record<string, unknown>)[`on${event.type}`];
        const list = [...(this.listeners.get(event.type) ?? [])];
        for (const listener of list) {
            if (listener.once) this.removeEventListener(event.type, listener.callback);
            try {
                listener.callback.call(this, event);
            } catch (error) {
                queueMicrotask(() => { throw error; });
            }
        }
        if (typeof handler === "function") handler.call(this, event);
        return !event.defaultPrevented;
    }
}

export class AbortSignal extends EventTarget {
    aborted = false;
    reason: unknown = undefined;
    onabort: ((event: Event) => void) | null = null;

    throwIfAborted(): void {
        if (this.aborted) throw this.reason;
    }

    static abort(reason?: unknown): AbortSignal {
        const controller = new AbortController();
        controller.abort(reason);
        return controller.signal;
    }

    static timeout(ms: number): AbortSignal {
        const controller = new AbortController();
        setTimeout(() => controller.abort(new DOMException("The operation timed out", "TimeoutError")), ms);
        return controller.signal;
    }

    static any(signals: AbortSignal[]): AbortSignal {
        const controller = new AbortController();
        for (const signal of signals) {
            if (signal.aborted) {
                controller.abort(signal.reason);
                break;
            }
            signal.addEventListener("abort", () => controller.abort(signal.reason), { once: true, signal: controller.signal });
        }
        return controller.signal;
    }
}

export class AbortController {
    readonly signal = new AbortSignal();

    abort(reason?: unknown): void {
        if (this.signal.aborted) return;
        this.signal.aborted = true;
        this.signal.reason = reason === undefined ? new DOMException("This operation was aborted", "AbortError") : reason;
        this.signal.dispatchEvent(new Event("abort"));
    }
}

export function installAbort(target: Record<string, unknown>): void {
    Object.assign(target, { DOMException, Event, EventTarget, AbortSignal, AbortController });
}
