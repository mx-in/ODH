import { expect, test } from "bun:test";
import Ajv2020 from "ajv/dist/2020.js";
import schema from "@baron/api/schema/manifest-1.json" with { type: "json" };
import type { PluginManifest } from "@baron/api";
import manifestJSON from "../manifest.json" with { type: "json" };
import en from "../locales/en.json" with { type: "json" };

// Baron's Swift validator checks the same file in macos/Tests/BaronCoreTests/Plugins/OdhManifestTests.swift.
const manifest = manifestJSON as unknown as PluginManifest;
const validate = new Ajv2020({ allErrors: true, strict: true }).compile(schema);

test("ODH's manifest passes the JSON Schema", () => {
    expect(validate(manifestJSON) ? [] : validate.errors).toEqual([]);
});

test("every ODH option has a preference, except the ones Baron replaces", () => {
    const ids = new Set(manifest.preferences?.map((p) => p.id));
    const odhOptions = ["maxcontext", "maxexample", "monolingual", "preferredaudio", "services", "ankiconnecturl", "duplicate", "tags",
        "deckname", "typename", "expression", "reading", "extrainfo", "definition", "definitions", "sentence", "url", "audio",
        "sysscripts", "udfscripts", "dictSelected"];
    expect(odhOptions.filter((id) => !ids.has(id))).toEqual([]);
    // enabled → the plugin switch, mouseselection → Run on selection, hotkey (hover) → dropped.
    for (const replaced of ["enabled", "mouseselection", "hotkey"]) expect(ids.has(replaced)).toBe(false);
});

test("every %key% has an English string", () => {
    const keys = JSON.stringify(manifestJSON).match(/"%[A-Za-z0-9_.-]+%"/g) ?? [];
    expect(keys.map((k) => k.slice(2, -2)).filter((k) => !(k in en))).toEqual([]);
});
