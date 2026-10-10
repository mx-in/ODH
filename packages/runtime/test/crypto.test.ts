import { describe, expect, test } from "bun:test";
import { createSandbox } from "./support/sandbox.ts";

describe("crypto in the prelude", () => {
    test("digest matches the platform for every algorithm", async () => {
        const box = await createSandbox();
        for (const algorithm of ["SHA-1", "SHA-256", "SHA-384", "SHA-512"]) {
            const ours = await box.run(`crypto.subtle.digest("${algorithm}", new TextEncoder().encode("狐 fox")).then((b) => Array.from(new Uint8Array(b)))`);
            const theirs = Array.from(new Uint8Array(await crypto.subtle.digest(algorithm, new TextEncoder().encode("狐 fox"))));
            expect(ours).toEqual(theirs);
        }
        await expect(box.run(`crypto.subtle.digest("MD5", new Uint8Array(1))`)).rejects.toMatchObject({ name: "NotSupportedError" });
    });

    test("getRandomValues fills integer arrays and refuses others", async () => {
        const box = await createSandbox();
        expect(box.run(`crypto.getRandomValues(new Uint32Array(8)).some((x) => x !== 0)`)).toBe(true);
        expect(() => box.run(`crypto.getRandomValues(new Float64Array(2))`)).toThrow();
        expect(() => box.run(`crypto.getRandomValues(new Uint8Array(65537))`)).toThrow();
    });

    test("randomUUID makes version 4 UUIDs", async () => {
        const box = await createSandbox();
        const ids = box.run(`[crypto.randomUUID(), crypto.randomUUID()]`) as string[];
        for (const id of ids) expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
        expect(ids[0]).not.toBe(ids[1]);
    });
});
