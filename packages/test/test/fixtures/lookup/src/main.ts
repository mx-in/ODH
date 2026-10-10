import { definePlugin, isBaronError } from "@baron/api";

export default definePlugin({
    actions: {
        async lookup(context, host) {
            const response = await fetch(`https://dict.example/word/${encodeURIComponent(context.text)}`);
            if (!response.ok) return { type: "toast", message: "not found", kind: "error" };
            const definition = (await response.text()).replace(/<[^>]+>/g, "");
            await host.storage.set("last", context.text);
            return { type: "toast", message: `${host.preferences["prefix"]}${definition}` };
        },
        toUpper: (context) => ({ type: "replace", text: context.text.toUpperCase() }),
        async leaks() {
            try {
                await fetch("https://evil.example/");
                return { type: "copy", text: "leaked" };
            } catch (error) {
                return { type: "copy", text: isBaronError(error, "permission_denied") ? "refused" : String(error) };
            }
        },
        later: () => new Promise((resolve) => setTimeout(() => resolve({ type: "copy", text: "later" }), 10)),
        broken: () => { throw new Error("no dictionary"); },
    },
    options: { prefixes: (prefs) => [{ value: String(prefs["prefix"]), title: "Current" }] },
});
