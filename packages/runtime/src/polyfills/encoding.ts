import { base64ToBytes, bytesToBase64 } from "@baron/api";

/** UTF-8 only, as the design says; enough for HTTP bodies and hashing. */
export class TextEncoder {
    readonly encoding = "utf-8";

    encode(input = ""): Uint8Array {
        const text = String(input);
        const bytes: number[] = [];
        for (let i = 0; i < text.length; i++) {
            let code = text.charCodeAt(i);
            if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
                const next = text.charCodeAt(i + 1);
                if (next >= 0xdc00 && next <= 0xdfff) {
                    code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
                    i++;
                }
            }
            if (code >= 0xd800 && code <= 0xdfff) code = 0xfffd;
            if (code < 0x80) bytes.push(code);
            else if (code < 0x800) bytes.push(0xc0 | (code >> 6), 0x80 | (code & 63));
            else if (code < 0x10000) bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
            else bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
        }
        return Uint8Array.from(bytes);
    }

    encodeInto(input: string, destination: Uint8Array): { read: number; written: number } {
        let read = 0, written = 0;
        for (const char of String(input)) {
            const bytes = this.encode(char);
            if (written + bytes.length > destination.length) break;
            destination.set(bytes, written);
            written += bytes.length;
            read += char.length;
        }
        return { read, written };
    }
}

export class TextDecoder {
    readonly encoding = "utf-8";
    readonly fatal: boolean;
    readonly ignoreBOM: boolean;

    constructor(label = "utf-8", options: { fatal?: boolean; ignoreBOM?: boolean } = {}) {
        if (!/^\s*(utf-?8|unicode-1-1-utf-8)\s*$/i.test(label)) throw new RangeError(`TextDecoder supports only UTF-8, not ${label}`);
        this.fatal = Boolean(options.fatal);
        this.ignoreBOM = Boolean(options.ignoreBOM);
    }

    decode(input?: ArrayBuffer | ArrayBufferView): string {
        if (input === undefined) return "";
        const bytes = input instanceof ArrayBuffer ? new Uint8Array(input) : new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
        let out = "";
        const bad = () => {
            if (this.fatal) throw new TypeError("The encoded data was not valid UTF-8");
            out += "\ufffd";
        };
        // The WHATWG UTF-8 decoder: one replacement character per maximal invalid subsequence.
        let code = 0, needed = 0, seen = 0, lower = 0x80, upper = 0xbf;
        let i = !this.ignoreBOM && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf ? 3 : 0;
        while (i < bytes.length) {
            const byte = bytes[i]!;
            if (needed === 0) {
                i++;
                if (byte <= 0x7f) out += String.fromCharCode(byte);
                else if (byte >= 0xc2 && byte <= 0xdf) { needed = 1; code = byte & 0x1f; }
                else if (byte >= 0xe0 && byte <= 0xef) { lower = byte === 0xe0 ? 0xa0 : 0x80; upper = byte === 0xed ? 0x9f : 0xbf; needed = 2; code = byte & 0xf; }
                else if (byte >= 0xf0 && byte <= 0xf4) { lower = byte === 0xf0 ? 0x90 : 0x80; upper = byte === 0xf4 ? 0x8f : 0xbf; needed = 3; code = byte & 0x7; }
                else bad();
                continue;
            }
            if (byte < lower || byte > upper) {
                code = needed = seen = 0; lower = 0x80; upper = 0xbf;
                bad();
                continue; // reprocess this byte
            }
            i++;
            lower = 0x80; upper = 0xbf;
            code = (code << 6) | (byte & 0x3f);
            if (++seen === needed) {
                out += String.fromCodePoint(code);
                code = needed = seen = 0;
            }
        }
        if (needed !== 0) bad();
        return out;
    }
}

const invalidCharacter = (message: string) => Object.assign(new Error(message), { name: "InvalidCharacterError" });

/** Latin-1 text to base64, as in browsers. */
export function btoa(data: unknown): string {
    const text = String(data);
    const bytes = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        if (code > 255) throw invalidCharacter("btoa: the string has characters outside Latin-1");
        bytes[i] = code;
    }
    return bytesToBase64(bytes);
}

export function atob(data: unknown): string {
    let bytes: Uint8Array;
    try {
        bytes = base64ToBytes(String(data));
    } catch {
        throw invalidCharacter("atob: the string is not valid base64");
    }
    let out = "";
    for (const byte of bytes) out += String.fromCharCode(byte);
    return out;
}

/** Deep copies the values the structured clone algorithm allows, keeping cycles and shared references. */
export function structuredClone<T>(value: T): T {
    const seen = new Map<unknown, unknown>();
    const clone = (input: unknown): unknown => {
        if (input === null || typeof input !== "object") {
            if (typeof input === "function" || typeof input === "symbol") throw dataClone(`${typeof input} values can't be cloned`);
            return input;
        }
        if (seen.has(input)) return seen.get(input);
        if (input instanceof Date) return remember(input, new Date(input.getTime()));
        if (input instanceof RegExp) return remember(input, new RegExp(input.source, input.flags));
        if (input instanceof ArrayBuffer) return remember(input, input.slice(0));
        if (ArrayBuffer.isView(input)) {
            const view = input as unknown as { constructor: new (b: ArrayBuffer, o: number, l: number) => unknown; buffer: ArrayBuffer; byteOffset: number; length?: number; byteLength: number };
            const copy = view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength);
            return remember(input, input instanceof DataView ? new DataView(copy) : new view.constructor(copy, 0, view.length ?? view.byteLength));
        }
        if (input instanceof Map) {
            const out = remember(input, new Map());
            for (const [k, v] of input) out.set(clone(k), clone(v));
            return out;
        }
        if (input instanceof Set) {
            const out = remember(input, new Set());
            for (const v of input) out.add(clone(v));
            return out;
        }
        if (input instanceof Error) {
            const out = remember(input, new Error(input.message));
            out.name = input.name;
            return out;
        }
        if (Array.isArray(input)) {
            const out = remember(input, [] as unknown[]);
            input.forEach((v, i) => (out[i] = clone(v)));
            return out;
        }
        const proto = Object.getPrototypeOf(input);
        if (proto !== Object.prototype && proto !== null) throw dataClone(`${proto?.constructor?.name ?? "This"} objects can't be cloned`);
        const out = remember(input, {} as Record<string, unknown>);
        for (const key of Object.keys(input)) out[key] = clone((input as Record<string, unknown>)[key]);
        return out;
    };
    const remember = <V>(from: unknown, to: V): V => (seen.set(from, to), to);
    return clone(value) as T;
}

const dataClone = (message: string) => Object.assign(new Error(message), { name: "DataCloneError" });

export function installEncoding(target: Record<string, unknown>): void {
    Object.assign(target, { TextEncoder, TextDecoder, atob, btoa, structuredClone });
}
