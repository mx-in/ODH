/**
 * Errors from host calls. Design: docs/design/plugin-platform/03-host-api-and-ipc.md#error-codes
 */

export const errorCodes = [
    /** Not granted; `data.permission` names it, `data.requestable` says whether `permissions.request` can ask. */
    "permission_denied",
    /** Needs a click on the plugin's button or panel within the last 5 s. */
    "user_action_required",
    /** Wrong type or value; `data.path` points at it. */
    "invalid_argument",
    /** DNS, TLS or connection failure; `data.reason`. */
    "network_error",
    /** The call or the dispatch ran out of time. */
    "timeout",
    /** Storage or cache full; `data.limit`, `data.used`. */
    "quota_exceeded",
    /** A missing view, file or key where that is an error. */
    "not_found",
    /** The plugin host restarted, or the panel closed. */
    "unavailable",
    /** A bug in Baron; reported with a log reference. */
    "internal",
] as const;

export type ErrorCode = (typeof errorCodes)[number];

/**
 * A failed host call. The prelude and the plugin's own bundle may each hold a copy of this class,
 * so test errors with `isBaronError` rather than `instanceof`.
 */
export class BaronError extends Error {
    override readonly name = "BaronError";
    readonly code: ErrorCode;
    readonly data: Readonly<Record<string, unknown>> | undefined;

    constructor(code: ErrorCode, message: string, data?: Record<string, unknown>) {
        super(message);
        this.code = code;
        this.data = data;
    }
}

export function isBaronError(error: unknown, code?: ErrorCode): error is BaronError {
    if (typeof error !== "object" || error === null) return false;
    const candidate = error as { name?: unknown; code?: unknown };
    return (
        candidate.name === "BaronError" &&
        (errorCodes as readonly unknown[]).includes(candidate.code) &&
        (code === undefined || candidate.code === code)
    );
}
