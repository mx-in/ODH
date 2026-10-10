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
