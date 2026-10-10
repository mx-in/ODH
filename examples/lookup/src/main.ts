import { definePlugin, isBaronError } from "@baron/api";

interface Suggestion {
    data?: { entries?: Array<{ entry: string; explain: string }> };
}

/** Gives up on a slow network well before Baron's 10 s action limit. */
const requestTimeout = 8000;

export default definePlugin({
    actions: {
        async define(context, host) {
            const word = context.text.trim().toLowerCase();
            const url = `https://dict.youdao.com/suggest?num=1&doctype=json&q=${encodeURIComponent(word)}`;
            try {
                const response = await fetch(url, { signal: AbortSignal.any([host.signal, AbortSignal.timeout(requestTimeout)]) });
                if (!response.ok) return { type: "toast", message: `The dictionary answered ${response.status}.`, kind: "error" };
                const entry = ((await response.json()) as Suggestion).data?.entries?.find((e) => e.entry.toLowerCase() === word);
                if (!entry) return { type: "toast", message: `No definition found for “${word}”.` };
                return { type: "toast", message: `${entry.entry}: ${entry.explain}` };
            } catch (error) {
                const name = (error as { name?: unknown } | null)?.name;
                if (isBaronError(error, "network_error") || isBaronError(error, "timeout") || name === "TimeoutError" || name === "AbortError") {
                    return { type: "toast", message: "The dictionary can't be reached.", kind: "error" };
                }
                throw error;
            }
        },
    },
});
