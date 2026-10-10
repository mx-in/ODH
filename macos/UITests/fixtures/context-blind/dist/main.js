// Prebuilt on purpose: the UI test needs no Bun. Toasts which context fields arrived, then the sentence.
globalThis.__baronPlugin = {
    actions: {
        read(context) {
            const fields = ["window", "page", "sentence", "paragraph"].filter((field) => context[field] !== undefined);
            const sentence = context.sentence ? context.sentence.text : "";
            return { type: "toast", message: `context: ${fields.join(",") || "none"} | ${sentence}` };
        },
    },
};
