import { expect, test } from "bun:test";
import type { ActionResult, SelectionContext } from "../src/index.ts";

// These checks run in `tsc`; the runtime test only keeps bun from skipping the file.

const copyOnly = {
    text: "fox",
    source: "key-copy",
    editable: false,
    app: { id: "com.example.app", name: "Example", pid: 42 },
    platform: "macos",
} satisfies SelectionContext;

const full = {
    ...copyOnly,
    source: "ax-web",
    html: "<b>fox</b>",
    window: { title: "Foxes", documentUrl: "file:///tmp/foxes.txt" },
    page: { url: "https://example.com/foxes", title: "Foxes" },
    sentence: { text: "The fox runs.", selectionStart: 4, selectionEnd: 7, truncated: false },
    paragraph: { text: "The fox runs. It is quick.", selectionStart: 4, selectionEnd: 7, truncated: false },
    bounds: { x: 10, y: 20, width: 30, height: 14 },
} satisfies SelectionContext;

const results: ActionResult[] = [
    { type: "copy", text: "FOX" },
    { type: "replace", text: "FOX" },
    { type: "toast", message: "a small wild dog", kind: "info" },
    { type: "openUrl", url: "https://example.com" },
    undefined,
];

// @ts-expect-error results are a closed set
const unknownResult: ActionResult = { type: "speak", text: "fox" };

// @ts-expect-error the source is a closed set
const badSource: SelectionContext = { ...copyOnly, source: "ocr" };

test("context and result types accept the documented shapes", () => {
    expect(full.sentence.text.slice(full.sentence.selectionStart, full.sentence.selectionEnd)).toBe("fox");
    expect(results).toHaveLength(5);
    expect([unknownResult, badSource]).toHaveLength(2);
});
