import { describe, expect, test } from "bun:test";
import schema from "../schema/manifest-1.json" with { type: "json" };
import type { ManifestAction, PluginManifest, Preference, PreferenceOption, PreferenceType, WhenRules } from "../src/index.ts";

// Each list is typed Record<keyof T, true>, so tsc fails when a key is missing or extra;
// the tests then fail when the schema's properties differ from the list.

const manifestKeys: Record<keyof PluginManifest, true> = {
    $schema: true, id: true, name: true, description: true, version: true, apiVersion: true, author: true,
    homepage: true, license: true, defaultLocale: true, main: true, icon: true, platforms: true,
    minBaronVersion: true, permissions: true, optionalPermissions: true, preferences: true,
    settingsPage: true, settingsView: true, actions: true,
};
const actionKeys: Record<keyof ManifestAction, true> = { id: true, run: true, title: true, icon: true, when: true, needs: true, autoRun: true };
const whenKeys: Record<keyof WhenRules, true> = {
    minLength: true, maxLength: true, regex: true, contentTypes: true, apps: true, excludeApps: true, editable: true,
};
const optionKeys: Record<keyof PreferenceOption, true> = { value: true, title: true, subtitle: true };

type KeysOf<T extends PreferenceType> = Record<keyof Extract<Preference, { type: T }>, true>;
const base = { id: true, type: true, title: true, description: true } as const;
const preferenceKeys: { [T in PreferenceType]: KeysOf<T> } = {
    text: { ...base, required: true, default: true, placeholder: true, multiline: true, pattern: true, maxLength: true },
    number: { ...base, required: true, default: true, min: true, max: true, step: true },
    checkbox: { ...base, required: true, default: true, label: true },
    dropdown: { ...base, required: true, default: true, options: true, optionsFrom: true, dependsOn: true },
    checklist: { ...base, required: true, default: true, options: true, optionsFrom: true, dependsOn: true },
    list: { ...base, required: true, default: true, itemPlaceholder: true, itemPattern: true, maxItems: true },
    secret: { ...base, required: true, placeholder: true },
    file: { ...base, required: true, extensions: true },
    directory: { ...base, required: true },
    app: { ...base, required: true, default: true },
    button: { ...base, run: true, label: true },
    heading: { ...base },
};

type Properties = { properties?: Record<string, unknown> };
const keys = (object: object) => Object.keys(object).sort();
const propertiesOf = (...schemas: Properties[]) => [...new Set(schemas.flatMap((s) => Object.keys(s.properties ?? {})))].sort();

describe("the schema and the TypeScript types list the same fields", () => {
    test("manifest", () => expect(propertiesOf(schema)).toEqual(keys(manifestKeys)));
    test("action", () => expect(propertiesOf(schema.$defs.action)).toEqual(keys(actionKeys)));
    test("when rules", () => expect(propertiesOf(schema.$defs.when)).toEqual(keys(whenKeys)));
    test("preference option", () => expect(propertiesOf(schema.$defs.preferenceOption)).toEqual(keys(optionKeys)));

    test("preference types", () => {
        const branches = schema.$defs.preference.allOf;
        expect(branches.map((b) => b.if.properties.type.const).sort()).toEqual(keys(preferenceKeys));
        expect(schema.$defs.preference.properties.type.enum.slice().sort()).toEqual(keys(preferenceKeys));
        for (const branch of branches) {
            const type = branch.if.properties.type.const as PreferenceType;
            const then = branch.then as Properties & { oneOf?: Properties[] };
            expect({ type, keys: propertiesOf(schema.$defs.preference, then, ...(then.oneOf ?? [])) }).toEqual({ type, keys: keys(preferenceKeys[type]) });
        }
    });
});
