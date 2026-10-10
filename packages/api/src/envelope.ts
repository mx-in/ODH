/**
 * The messages between Baron and a plugin's engine context or page. Plugins never see them;
 * the prelude and the page bridge build them. Design: docs/design/plugin-platform/03-host-api-and-ipc.md#messages
 */
import type { SelectionContext } from "./context.ts";
import type { ErrorCode } from "./errors.ts";
import type { Environment, Preferences } from "./host.ts";

export const envelopeVersion = 1;

/** Plugin → Baron: a host method call. */
export interface CallEnvelope {
    v: 1;
    kind: "call";
    id: number;
    ns: string;
    method: string;
    args: unknown[];
}

/** The plugin's own code threw or rejected, as opposed to a host call failing. */
export type EnvelopeErrorCode = ErrorCode | "plugin_error";

export interface EnvelopeError {
    code: EnvelopeErrorCode;
    message: string;
    data?: Record<string, unknown>;
    /** Only for plugin errors. */
    stack?: string;
}

/** Either direction: the answer to a call (to the plugin) or to a dispatch (to Baron), matched by `id`. */
export type ResultEnvelope =
    | { v: 1; kind: "result"; id: number; ok: true; value?: unknown }
    | { v: 1; kind: "result"; id: number; ok: false; error: EnvelopeError };

export type DispatchTarget = "action" | "options" | "button" | "lifecycle" | "event";

/** Baron → plugin: run one of the plugin's exports. */
export interface DispatchEnvelope {
    v: 1;
    kind: "dispatch";
    id: number;
    target: DispatchTarget;
    /** The export: an action's handler, an options provider, a button, `onInstall` or `onUpdate`. */
    name: string;
    payload: DispatchPayload;
}

export interface DispatchPayload {
    environment: Environment;
    preferences: Preferences;
    /** For actions. */
    context?: SelectionContext;
    /** For lifecycle `onUpdate`: `{ previousVersion }`; for events: the event's arguments. */
    args?: unknown[];
}

/** Baron → plugin: a dispatch ran out of time or its caller went away; abort its signal. */
export interface CancelEnvelope {
    v: 1;
    kind: "cancel";
    id: number;
}

/** Baron → plugin: an event for an open view (task-010). */
export interface EventEnvelope {
    v: 1;
    kind: "event";
    view: string;
    name: string;
    payload: unknown;
}

export type Envelope = CallEnvelope | ResultEnvelope | DispatchEnvelope | CancelEnvelope | EventEnvelope;

// Bytes travel as { "$bytes": "<base64>" }; nothing else needs encoding in JSON.

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

export function bytesToBase64(bytes: Uint8Array): string {
    let out = "";
    for (let i = 0; i < bytes.length; i += 3) {
        const a = bytes[i]!, b = bytes[i + 1], c = bytes[i + 2];
        const n = (a << 16) | ((b ?? 0) << 8) | (c ?? 0);
        out += alphabet[(n >> 18) & 63]! + alphabet[(n >> 12) & 63]!;
        out += b === undefined ? "=" : alphabet[(n >> 6) & 63]!;
        out += c === undefined ? "=" : alphabet[n & 63]!;
    }
    return out;
}

export function base64ToBytes(text: string): Uint8Array {
    const clean = text.replace(/[\s=]/g, "");
    if (/[^A-Za-z0-9+/]/.test(clean) || clean.length % 4 === 1) throw new TypeError("Invalid base64");
    const out = new Uint8Array(Math.floor((clean.length * 3) / 4));
    let bits = 0, buffer = 0, index = 0;
    for (const char of clean) {
        buffer = (buffer << 6) | alphabet.indexOf(char);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[index++] = (buffer >> bits) & 255;
        }
    }
    return out;
}

/** Replaces every Uint8Array (at any depth) with `{ $bytes }`, so the value survives JSON. */
export function encodeValue(value: unknown): unknown {
    if (value instanceof Uint8Array) return { $bytes: bytesToBase64(value) };
    if (Array.isArray(value)) return value.map(encodeValue);
    if (value !== null && typeof value === "object") {
        return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encodeValue(v)]));
    }
    return value;
}

/** Turns every `{ $bytes }` back into a Uint8Array. */
export function decodeValue(value: unknown): unknown {
    if (Array.isArray(value)) return value.map(decodeValue);
    if (value !== null && typeof value === "object") {
        const entries = Object.entries(value);
        if (entries.length === 1 && entries[0]![0] === "$bytes" && typeof entries[0]![1] === "string") {
            return base64ToBytes(entries[0]![1]);
        }
        return Object.fromEntries(entries.map(([k, v]) => [k, decodeValue(v)]));
    }
    return value;
}
