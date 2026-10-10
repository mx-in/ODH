import { definePlugin, isBaronError } from "@baron/api";

interface Entry {
    word: string;
    meanings: Array<{ partOfSpeech: string; definitions: Array<{ definition: string }> }>;
}

export default definePlugin({
    actions: {
        async define(context, host) {
            const word = context.text.trim().toLowerCase();
            try {
                const response = await fetch(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`, { signal: host.signal });
                if (response.status === 404) return { type: "toast", message: `No definition found for “${word}”.` };
                if (!response.ok) return { type: "toast", message: `The dictionary answered ${response.status}.`, kind: "error" };
                const [entry] = (await response.json()) as Entry[];
                const meaning = entry?.meanings[0];
                const definition = meaning?.definitions[0]?.definition;
                if (!entry || !meaning || !definition) return { type: "toast", message: `No definition found for “${word}”.` };
                return { type: "toast", message: `${entry.word} (${meaning.partOfSpeech}): ${definition}` };
            } catch (error) {
                if (isBaronError(error, "network_error") || isBaronError(error, "timeout")) {
                    return { type: "toast", message: "The dictionary can't be reached.", kind: "error" };
                }
                throw error;
            }
        },
    },
});
