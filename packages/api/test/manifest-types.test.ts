import { expect, test } from "bun:test";
import type { Preference, PluginManifest } from "../src/index.ts";

// These checks run in `tsc`; the runtime test only keeps bun from skipping the file.

const minimal = {
    id: "org.example.upper",
    name: "Upper",
    description: "Uppercases the selection",
    version: "1.0.0",
    apiVersion: 1,
    main: "dist/main.js",
    actions: [{ id: "upper", title: "UPPER" }],
} satisfies PluginManifest;

const everyPreference: Preference[] = [
    { id: "url", type: "text", title: "URL", default: "http://127.0.0.1:8765", pattern: "^https?://" },
    { id: "max", type: "number", title: "Max", min: 1, max: 10, step: 1, default: 3 },
    { id: "on", type: "checkbox", title: "On", label: "Enabled", default: true },
    { id: "deck", type: "dropdown", title: "Deck", optionsFrom: "decks", dependsOn: ["url"] },
    { id: "audio", type: "dropdown", title: "Audio", options: [{ value: "uk", title: "UK" }], default: "uk" },
    { id: "dicts", type: "checklist", title: "Dictionaries", optionsFrom: "dictionaries" },
    { id: "scripts", type: "list", title: "Scripts", itemPattern: "^https://", maxItems: 20 },
    { id: "key", type: "secret", title: "API key", required: true },
    { id: "deckFile", type: "file", title: "File", extensions: ["json"] },
    { id: "folder", type: "directory", title: "Folder" },
    { id: "target", type: "app", title: "App" },
    { id: "test", type: "button", title: "", label: "Test connection", run: "testAnki" },
    { id: "anki", type: "heading", title: "Anki" },
];

// @ts-expect-error a manifest needs at least one action
const noActions: PluginManifest = { ...minimal, actions: [] };

// @ts-expect-error options and optionsFrom can't both be given
const bothOptions: Preference = { id: "d", type: "dropdown", title: "D", options: [], optionsFrom: "x" };

// @ts-expect-error buttons can't be required
const requiredButton: Preference = { id: "b", type: "button", title: "", label: "Go", run: "go", required: true };

// @ts-expect-error unknown permission names are rejected (`network:*` outside optionalPermissions is caught by the schema)
const unknownPermission: PluginManifest = { ...minimal, permissions: ["context.foo"] };

test("manifest types accept the documented shapes", () => {
    expect(minimal.actions).toHaveLength(1);
    expect(everyPreference).toHaveLength(13);
    expect([noActions, bothOptions, requiredButton, unknownPermission]).toHaveLength(4);
});
