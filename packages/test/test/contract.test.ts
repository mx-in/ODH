import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import contract from "../contract/host-contract.json" with { type: "json" };
import { createHarness } from "../src/index.ts";

/** Whether `actual` has every field of `expected` (deep), so Baron may add fields such as headers. */
export function containsExpected(actual: unknown, expected: unknown): boolean {
    if (expected === null || typeof expected !== "object") return actual === expected;
    if (Array.isArray(expected)) return Array.isArray(actual) && actual.length === expected.length && expected.every((e, i) => containsExpected(actual[i], e));
    return typeof actual === "object" && actual !== null && Object.entries(expected).every(([k, v]) => containsExpected((actual as Record<string, unknown>)[k], v));
}

const plugin = join(import.meta.dir, "..", "contract", "plugin");

describe.each(["jsc", "quickjs"] as const)("host contract against the mock host on %s", (engine) => {
    for (const c of contract.cases) {
        test(c.name, async () => {
            const h = await createHarness({ plugin, engine, permissions: { permissions: c.permissions ?? [], optionalPermissions: c.optional ?? [] } });
            h.host.clipboard = contract.clipboard;
            h.host.promptAnswer = contract.promptAnswer as "deny";
            if (c.mock) h.http.mock(c.mock.url, { status: c.mock.status, body: c.mock.body });
            const [ns, method, args] = c.call as [string, string, unknown[]];
            const result = (await h.runAction("call", { text: JSON.stringify({ ns, method, args }), editable: true }, { click: c.userAction !== false })) as { text: string };
            const answer = JSON.parse(result.text) as { ok: boolean; value?: unknown; code?: string };
            h.close();
            if ("code" in c.expect) expect(answer).toEqual({ ok: false, code: c.expect.code });
            else expect({ ok: answer.ok, matches: containsExpected(answer.value, c.expect.value), value: answer.value }).toMatchObject({ ok: true, matches: true });
        });
    }
});
