import { BaronError, decodeValue, encodeValue, type CallEnvelope, type Envelope, type EnvelopeError, type ErrorCode } from "@baron/api";
import type { BaronNative } from "./native.ts";

type Pending = { resolve(value: unknown): void; reject(error: unknown): void };

/** Numbers calls, sends them, and settles each one when its result arrives. */
export class Channel {
    private nextID = 1;
    private readonly pending = new Map<number, Pending>();
    /** Gets every envelope that isn't the result of a call. */
    onEnvelope: (envelope: Envelope) => void = () => {};

    constructor(private readonly native: BaronNative) {}

    call(ns: string, method: string, args: unknown[]): Promise<unknown> {
        const id = this.nextID++;
        const envelope: CallEnvelope = { v: 1, kind: "call", id, ns, method, args: encodeValue(args) as unknown[] };
        return new Promise((resolve, reject) => {
            this.pending.set(id, { resolve, reject });
            this.send(envelope);
        });
    }

    /** A call whose answer nobody waits for, such as a log line. */
    notify(ns: string, method: string, args: unknown[]): void {
        this.call(ns, method, args).catch(() => {});
    }

    send(envelope: Envelope): void {
        this.native.send(JSON.stringify(envelope));
    }

    receive(json: string): void {
        const envelope = JSON.parse(json) as Envelope;
        if (envelope.kind !== "result") return this.onEnvelope(envelope);
        const pending = this.pending.get(envelope.id);
        if (!pending) return;
        this.pending.delete(envelope.id);
        if (envelope.ok) pending.resolve(decodeValue(envelope.value));
        else pending.reject(toError(envelope.error));
    }

    get pendingCount(): number {
        return this.pending.size;
    }
}

export function toError(error: EnvelopeError): Error {
    if (error.code === "plugin_error") return new Error(error.message);
    return new BaronError(error.code as ErrorCode, error.message, error.data);
}
