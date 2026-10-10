import { base64ToBytes, bytesToBase64 } from "@baron/api";
import type { BaronNative } from "../native.ts";
import { DOMException } from "./abort.ts";

const algorithms: Record<string, string> = { "SHA-1": "SHA-1", "SHA-256": "SHA-256", "SHA-384": "SHA-384", "SHA-512": "SHA-512" };

type IntegerArray = Int8Array | Uint8Array | Uint8ClampedArray | Int16Array | Uint16Array | Int32Array | Uint32Array | BigInt64Array | BigUint64Array;

/** crypto.getRandomValues, randomUUID and subtle.digest, over the native side. */
export function createCrypto(native: BaronNative) {
    const getRandomValues = <T extends IntegerArray>(array: T): T => {
        if (!ArrayBuffer.isView(array) || array instanceof Float32Array || array instanceof Float64Array || array instanceof DataView) {
            throw new DOMException("getRandomValues needs an integer typed array", "TypeMismatchError");
        }
        if (array.byteLength > 65536) throw new DOMException("getRandomValues takes at most 65536 bytes", "QuotaExceededError");
        new Uint8Array(array.buffer, array.byteOffset, array.byteLength).set(native.randomBytes(array.byteLength));
        return array;
    };
    const randomUUID = (): string => {
        const b = getRandomValues(new Uint8Array(16));
        b[6] = (b[6]! & 0x0f) | 0x40;
        b[8] = (b[8]! & 0x3f) | 0x80;
        const hex = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
        return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
    };
    const digest = async (algorithm: string | { name: string }, data: ArrayBuffer | ArrayBufferView): Promise<ArrayBuffer> => {
        const name = algorithms[(typeof algorithm === "string" ? algorithm : algorithm.name).toUpperCase()];
        if (!name) throw new DOMException(`Unsupported digest algorithm`, "NotSupportedError");
        const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
        const out = base64ToBytes(native.digest(name, bytesToBase64(bytes)));
        return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength) as ArrayBuffer;
    };
    return Object.freeze({ getRandomValues, randomUUID, subtle: Object.freeze({ digest }) });
}

export function installCrypto(target: Record<string, unknown>, native: BaronNative): void {
    target["crypto"] = createCrypto(native);
}
