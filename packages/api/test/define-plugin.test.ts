import { expect, test } from "bun:test";
import { definePlugin } from "../src/index.ts";

const plugin = definePlugin({
    actions: {
        upper(context) {
            return { type: "replace", text: context.text.toUpperCase() };
        },
        async lookup(context, host) {
            const response = await host.http.fetch(`https://dict.example/${encodeURIComponent(context.text)}`);
            return { type: "toast", message: response.body };
        },
    },
    options: {
        decks: async () => [{ value: "Default", title: "Default" }],
    },
    buttons: {
        testAnki: () => ({ message: "Connected to AnkiConnect 6", kind: "success" }),
    },
    lifecycle: {
        onUpdate({ previousVersion }) {
            void previousVersion;
        },
    },
});

// @ts-expect-error an action can't return a result type Baron doesn't know
definePlugin({ actions: { bad: () => ({ type: "speak" }) } });

// @ts-expect-error actions are required
definePlugin({ options: {} });

test("definePlugin returns its definition unchanged", async () => {
    expect(Object.keys(plugin.actions)).toEqual(["upper", "lookup"]);
    const context = { text: "fox", source: "ax-text", editable: true, app: { id: "a", name: "A", pid: 1 }, platform: "macos" } as const;
    expect(await plugin.actions.upper(context)).toEqual({ type: "replace", text: "FOX" });
    expect(await plugin.options.decks()).toEqual([{ value: "Default", title: "Default" }]);
});
