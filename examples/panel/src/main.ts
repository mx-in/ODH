import { definePlugin, isBaronError } from "@baron/api";

interface Suggestion {
    data?: { entries?: Array<{ entry: string; explain: string }> };
}

/** What the page shows: views/panel.js reads it from baron.view.data. */
export interface PanelData {
    word: string;
    entries: Array<{ entry: string; explain: string }>;
}

/** Gives up on a slow network well before Baron's 10 s action limit. */
const requestTimeout = 8000;

export default definePlugin({
    actions: {
        async define(context, host) {
            const word = context.text.trim().toLowerCase();
            const url = `https://dict.youdao.com/suggest?num=5&doctype=json&q=${encodeURIComponent(word)}`;
            let entries: PanelData["entries"];
            try {
                const response = await fetch(url, { signal: AbortSignal.any([host.signal, AbortSignal.timeout(requestTimeout)]) });
                if (!response.ok) return { type: "toast", message: `The dictionary answered ${response.status}.`, kind: "error" };
                entries = ((await response.json()) as Suggestion).data?.entries ?? [];
            } catch (error) {
                const name = (error as { name?: unknown } | null)?.name;
                if (isBaronError(error, "network_error") || isBaronError(error, "timeout") || name === "TimeoutError" || name === "AbortError") {
                    return { type: "toast", message: "The dictionary can't be reached.", kind: "error" };
                }
                throw error;
            }
            if (entries.length === 0) return { type: "toast", message: `No definition found for “${word}”.` };

            const data: PanelData = { word, entries };
            const view = await host.ui.openWebView("views/panel.html", { data, height: 160 });
            // The page asks for a definition to be copied; its click counts as the user acting.
            view.onMessage(async (message) => {
                const copy = (message as { copy?: unknown }).copy;
                if (typeof copy !== "string") return;
                await host.clipboard.writeText(copy);
                await view.postMessage({ copied: copy });
            });
        },
    },
});
