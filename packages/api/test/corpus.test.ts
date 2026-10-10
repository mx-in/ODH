import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { schemaErrorPointers } from "./support/schema.ts";

// The corpus is shared with Baron's Swift validator (macos/Tests/BaronCoreTests). Each case is a
// plugin folder with manifest.json, expect.json and any files the manifest names.

type Expectation =
    | { description: string; valid: true }
    | { description: string; valid: false; rejectedBy: "schema" | "semantic"; pointer: string };

const root = join(import.meta.dir, "corpus");
const cases = readdirSync(root).sort().map((name) => ({
    name,
    manifest: JSON.parse(readFileSync(join(root, name, "manifest.json"), "utf8")) as unknown,
    expect: JSON.parse(readFileSync(join(root, name, "expect.json"), "utf8")) as Expectation,
}));

/** True when one pointer is the other, or contains it: errors about an object and about its fields are related. */
const related = (a: string, b: string) => a === b || a.startsWith(`${b}/`) || b.startsWith(`${a}/`);

describe("manifest corpus against the JSON Schema", () => {
    test("has at least 30 cases, named after what rejects them", () => {
        expect(cases.length).toBeGreaterThanOrEqual(30);
        for (const { name, expect: e } of cases) {
            expect(name.startsWith(e.valid ? "valid-" : `${e.rejectedBy}-`)).toBe(true);
        }
    });

    for (const { name, manifest, expect: e } of cases) {
        if (e.valid) {
            test(`${name}: accepted`, () => expect(schemaErrorPointers(manifest)).toEqual([]));
        } else if (e.rejectedBy === "semantic") {
            test(`${name}: passes the schema (only Baron rejects it)`, () => expect(schemaErrorPointers(manifest)).toEqual([]));
        } else {
            test(`${name}: rejected at ${e.pointer}`, () => {
                const pointers = schemaErrorPointers(manifest);
                expect(pointers).toContain(e.pointer);
                // Every error concerns the one defect, so a case can't hide a second mistake.
                expect(pointers.filter((p) => !related(p, e.pointer))).toEqual([]);
            });
        }
    }
});
