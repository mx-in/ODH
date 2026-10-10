import { describe, expect, test } from "bun:test";
import { schemaErrorPointers } from "./support/schema.ts";

const minimal = {
    id: "org.example.upper",
    name: "Upper",
    description: "Uppercases the selection",
    version: "1.0.0",
    apiVersion: 1,
    main: "dist/main.js",
    actions: [{ id: "upper", title: "UPPER" }],
};

describe("manifest schema: package fields and actions", () => {
    test("accepts a minimal manifest", () => {
        expect(schemaErrorPointers(minimal)).toEqual([]);
    });

    test("accepts every package field and action field", () => {
        const full = {
            ...minimal,
            $schema: "https://baron.dev/schema/manifest-1.json",
            author: "Example",
            homepage: "https://example.com",
            license: "MIT",
            defaultLocale: "zh-Hans",
            icon: "assets/icon.svg",
            platforms: ["macos", "linux"],
            minBaronVersion: "0.1.0-beta.2",
            permissions: ["context.sentence", "network:dict.cn", "network:*.youdao.com", "network:http://example.com", "network:127.0.0.1:8765", "network:api.example.com:8443"],
            optionalPermissions: ["network:*", "clipboard.read"],
            settingsPage: "views/settings.html",
            actions: [{
                id: "lookup", run: "lookUp", title: "%action.lookup%", icon: "assets/lookup.svg",
                when: { minLength: 1, maxLength: 64, regex: "^\\p{L}+$", contentTypes: ["word"], apps: ["com.apple.Safari", { macos: "com.google.Chrome", windows: "chrome.exe" }], excludeApps: ["com.apple.Terminal"], editable: false },
                needs: ["sentence", "page"], autoRun: "allowed",
            }],
        };
        expect(schemaErrorPointers(full)).toEqual([]);
    });

    test("points at missing, unknown and malformed fields", () => {
        const { id: _, ...noID } = minimal;
        expect(schemaErrorPointers(noID)).toEqual(["/id"]);
        expect(schemaErrorPointers({ ...minimal, permisions: [] })).toEqual(["/permisions"]);
        expect(schemaErrorPointers({ ...minimal, main: "../main.js" })).toEqual(["/main"]);
        expect(schemaErrorPointers({ ...minimal, permissions: ["network:*"] })).toEqual(["/permissions/0"]);
        expect(schemaErrorPointers({ ...minimal, actions: [{ id: "upper", title: "UPPER", when: { regex: "" } }] })).toEqual(["/actions/0/when/regex"]);
    });
});

describe("manifest schema: preferences", () => {
    const withPreferences = (...preferences: unknown[]) => ({ ...minimal, preferences });

    test("accepts all twelve preference types", () => {
        expect(schemaErrorPointers(withPreferences(
            { id: "anki", type: "heading", title: "Anki" },
            { id: "url", type: "text", title: "URL", default: "http://127.0.0.1:8765", pattern: "^https?://", placeholder: "http://…", multiline: false, maxLength: 200, required: true },
            { id: "max", type: "number", title: "Max", min: 1, max: 10, step: 1, default: 3 },
            { id: "on", type: "checkbox", title: "On", label: "Enabled", default: true, description: "Turns it on" },
            { id: "deck", type: "dropdown", title: "Deck", optionsFrom: "decks", dependsOn: ["url"] },
            { id: "audio", type: "dropdown", title: "Audio", options: [{ value: "uk", title: "UK", subtitle: "British" }], default: "uk" },
            { id: "dicts", type: "checklist", title: "Dictionaries", optionsFrom: "dictionaries", default: ["a"] },
            { id: "scripts", type: "list", title: "Scripts", itemPattern: "^https://", itemPlaceholder: "https://…", maxItems: 20, default: [] },
            { id: "key", type: "secret", title: "API key", placeholder: "sk-…" },
            { id: "deckFile", type: "file", title: "File", extensions: ["json"] },
            { id: "folder", type: "directory", title: "Folder" },
            { id: "target", type: "app", title: "App", default: "com.apple.Safari" },
            { id: "test", type: "button", title: "", label: "Test connection", run: "testAnki" },
        ))).toEqual([]);
    });

    test("allows a type's fields only on that type", () => {
        expect(schemaErrorPointers(withPreferences({ id: "x", type: "checkbox", title: "X", placeholder: "no" }))).toEqual(["/preferences/0/placeholder"]);
        expect(schemaErrorPointers(withPreferences({ id: "b", type: "button", title: "", label: "Go", run: "go", required: true }))).toEqual(["/preferences/0/required"]);
    });

    test("points at the field that is wrong or missing", () => {
        expect(schemaErrorPointers(withPreferences({ id: "b", type: "button", title: "", label: "Go" }))).toContain("/preferences/0/run");
        expect(schemaErrorPointers(withPreferences({ id: "n", type: "number", title: "N", default: "3" }))).toContain("/preferences/0/default");
        expect(schemaErrorPointers(withPreferences({ id: "x", type: "colour", title: "X" }))).toContain("/preferences/0/type");
    });

    test("needs exactly one of options and optionsFrom", () => {
        expect(schemaErrorPointers(withPreferences({ id: "d", type: "dropdown", title: "D" }))).toContain("/preferences/0");
        expect(schemaErrorPointers(withPreferences({ id: "d", type: "dropdown", title: "D", options: [], optionsFrom: "x" }))).toContain("/preferences/0");
    });
});
