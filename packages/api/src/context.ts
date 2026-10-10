/**
 * What an action receives and what it may return.
 * Design: docs/tec-design.md#context-capture and docs/design/plugin-platform/03-host-api-and-ipc.md#action-results
 */
import type { Platform } from "./manifest.ts";

/** A stretch of text around the selection. Offsets are UTF-16 code units, like JavaScript string indices. */
export interface TextSpan {
    text: string;
    /** Where the selection starts inside `text`. */
    selectionStart: number;
    selectionEnd: number;
    /** True when the span was cut to its cap (4,000 units for a paragraph, 1,000 for a sentence). */
    truncated: boolean;
}

/** How Baron read the text. Context fields are only filled for the Accessibility steps. */
export type SelectionSource = "ax-text" | "ax-web" | "menu-copy" | "key-copy" | "hotkey";

/**
 * The selection an action runs on. Every optional field may be missing, even with its permission,
 * when the app doesn't expose it; actions must still work with `text` alone.
 */
export interface SelectionContext {
    /** The selection, as plain text. */
    text: string;
    /** Only when the app supplied HTML. */
    html?: string;
    source: SelectionSource;
    /** Whether a result can replace the selection. */
    editable: boolean;
    /** `id` is the bundle ID on macOS. */
    app: { id: string; name: string; pid: number };
    /** Needs `context.window`. */
    window?: { title?: string; documentUrl?: string };
    /** Needs `context.page`. */
    page?: { url: string; title?: string };
    /** Needs `context.sentence`. */
    sentence?: TextSpan;
    /** Needs `context.paragraph`. */
    paragraph?: TextSpan;
    /** Screen points, top-left origin. */
    bounds?: { x: number; y: number; width: number; height: number };
    platform: Platform;
}

export type ToastKind = "info" | "success" | "error";

/** What Baron does after an action returns. Returning nothing is fine, for example after opening a panel. */
export type ActionResult =
    | { type: "copy"; text: string }
    /** Needs `selection.replace` and an editable selection. */
    | { type: "replace"; text: string }
    | { type: "toast"; message: string; kind?: ToastKind }
    | { type: "openUrl"; url: string }
    | void;
