import type { HttpResponse } from "@baron/api";
import type { Channel } from "../channel.ts";
import { DOMException } from "./abort.ts";
import { TextDecoder, TextEncoder } from "./encoding.ts";
import { URL as WhatwgURL, URLSearchParams } from "./url.ts";

type HeadersInit = Headers | Record<string, string> | Array<[string, string]>;

export class Headers {
    private readonly map = new Map<string, string>();

    constructor(init?: HeadersInit) {
        if (init instanceof Headers) init.forEach((value, name) => this.append(name, value));
        else if (Array.isArray(init)) for (const [name, value] of init) this.append(name, value);
        else if (init) for (const name of Object.keys(init)) this.append(name, init[name]!);
    }

    private static key(name: string): string {
        const key = String(name).toLowerCase();
        if (!/^[!#$%&'*+.^_`|~0-9a-z-]+$/.test(key)) throw new TypeError(`Invalid header name: ${name}`);
        return key;
    }

    append(name: string, value: string): void {
        const key = Headers.key(name);
        const text = String(value).trim();
        this.map.set(key, this.map.has(key) ? `${this.map.get(key)}, ${text}` : text);
    }
    set(name: string, value: string): void { this.map.set(Headers.key(name), String(value).trim()); }
    get(name: string): string | null { return this.map.get(Headers.key(name)) ?? null; }
    has(name: string): boolean { return this.map.has(Headers.key(name)); }
    delete(name: string): void { this.map.delete(Headers.key(name)); }
    forEach(callback: (value: string, name: string, headers: Headers) => void): void {
        for (const [name, value] of this.entries()) callback(value, name, this);
    }
    *entries(): IterableIterator<[string, string]> { yield* [...this.map.entries()].sort(([a], [b]) => (a < b ? -1 : 1)); }
    *keys(): IterableIterator<string> { for (const [name] of this.entries()) yield name; }
    *values(): IterableIterator<string> { for (const [, value] of this.entries()) yield value; }
    [Symbol.iterator](): IterableIterator<[string, string]> { return this.entries(); }
    toObject(): Record<string, string> { return Object.fromEntries(this.entries()); }
}

type BodyInit = string | Uint8Array | ArrayBuffer | ArrayBufferView | URLSearchParams | null | undefined;

function toBytes(body: BodyInit, headers: Headers): Uint8Array | undefined {
    if (body === null || body === undefined) return undefined;
    if (typeof body === "string") {
        if (!headers.has("content-type")) headers.set("content-type", "text/plain;charset=UTF-8");
        return new TextEncoder().encode(body);
    }
    if (body instanceof URLSearchParams) {
        if (!headers.has("content-type")) headers.set("content-type", "application/x-www-form-urlencoded;charset=UTF-8");
        return new TextEncoder().encode(body.toString());
    }
    if (body instanceof ArrayBuffer) return new Uint8Array(body.slice(0));
    if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength));
    throw new TypeError("Unsupported body: use a string, bytes or URLSearchParams");
}

class Body {
    bodyUsed = false;
    constructor(protected readonly bytesValue: Uint8Array | undefined) {}

    private consume(): Uint8Array {
        if (this.bodyUsed) throw new TypeError("Body has already been read");
        this.bodyUsed = true;
        return this.bytesValue ?? new Uint8Array(0);
    }
    async bytes(): Promise<Uint8Array> { return this.consume(); }
    async arrayBuffer(): Promise<ArrayBuffer> { const b = this.consume(); return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer; }
    async text(): Promise<string> { return new TextDecoder().decode(this.consume()); }
    async json(): Promise<unknown> { return JSON.parse(await this.text()); }
}

export type RequestInit = { method?: string; headers?: HeadersInit; body?: BodyInit; signal?: AbortSignal | null; redirect?: "follow" };

export class Request extends Body {
    readonly url: string;
    readonly method: string;
    readonly headers: Headers;
    readonly signal: AbortSignal | null;

    constructor(input: string | URL | Request, init: RequestInit = {}) {
        const from = input instanceof Request ? input : undefined;
        const headers = new Headers(init.headers ?? from?.headers);
        const method = String(init.method ?? from?.method ?? "GET").toUpperCase();
        const body = init.body !== undefined ? toBytes(init.body, headers) : from?.bytesValue;
        if (body && (method === "GET" || method === "HEAD")) throw new TypeError(`A ${method} request can't have a body`);
        super(body);
        this.url = new WhatwgURL(String(from ? from.url : input)).href;
        this.method = method;
        this.headers = headers;
        this.signal = init.signal ?? from?.signal ?? null;
    }

    clone(): Request {
        if (this.bodyUsed) throw new TypeError("Body has already been read");
        return new Request(this);
    }

    get bodyBytes(): Uint8Array | undefined { return this.bytesValue; }
}

export type ResponseInit = { status?: number; statusText?: string; headers?: HeadersInit };

export class Response extends Body {
    readonly status: number;
    readonly statusText: string;
    readonly headers: Headers;
    readonly ok: boolean;
    readonly type = "basic";
    url = "";
    redirected = false;

    constructor(body?: BodyInit, init: ResponseInit = {}) {
        const headers = new Headers(init.headers);
        super(toBytes(body, headers));
        this.status = init.status ?? 200;
        if (this.status < 200 || this.status > 599) throw new RangeError(`Invalid status ${this.status}`);
        this.statusText = init.statusText ?? "";
        this.headers = headers;
        this.ok = this.status >= 200 && this.status < 300;
    }

    clone(): Response {
        if (this.bodyUsed) throw new TypeError("Body has already been read");
        const copy = new Response(this.bytesValue, { status: this.status, statusText: this.statusText, headers: this.headers });
        copy.url = this.url;
        copy.redirected = this.redirected;
        return copy;
    }

    static json(data: unknown, init: ResponseInit = {}): Response {
        const headers = new Headers(init.headers);
        if (!headers.has("content-type")) headers.set("content-type", "application/json");
        return new Response(JSON.stringify(data), { ...init, headers });
    }
}

/** fetch over host.http: the same allowlist and limits, cancelled on the native side when aborted. */
export function createFetch(channel: Channel) {
    let nextRequest = 1;
    return async function fetch(input: string | URL | Request, init?: RequestInit): Promise<Response> {
        const request = new Request(input, init);
        const signal = request.signal;
        if (signal?.aborted) throw signal.reason;
        const requestID = nextRequest++;
        const call = channel.call("http", "fetch", [request.url, {
            method: request.method,
            headers: request.headers.toObject(),
            ...(request.bodyBytes ? { body: request.bodyBytes } : {}),
            responseType: "bytes",
            requestID,
        }]) as Promise<HttpResponse<Uint8Array>>;
        const aborted = signal && new Promise<never>((_, reject) => signal.addEventListener("abort", () => {
            channel.notify("http", "cancel", [requestID]);
            reject(signal.reason ?? new DOMException("The request was aborted", "AbortError"));
        }, { once: true }));
        const answer = await (aborted ? Promise.race([call, aborted]) : call);
        const response = new Response(answer.status === 204 || answer.status === 304 ? null : answer.body, { status: answer.status, headers: answer.headers });
        response.url = answer.url;
        response.redirected = answer.url !== request.url;
        return response;
    };
}

export function installFetch(target: Record<string, unknown>, channel: Channel): void {
    Object.assign(target, { fetch: createFetch(channel), Request, Response, Headers });
}
