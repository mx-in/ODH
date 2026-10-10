/**
 * Builds the plugin's locales/<tag>.json from the extension's src/_locales/<dir>/messages.json,
 * plus strings only the Baron plugin needs (messages/<tag>.json). Run `npm run locales -w plugins/odh`
 * after changing either; a test fails while the committed files are out of date.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/** Baron locale tag → Chrome extension locale folder. */
export const sources = { en: "en", "zh-Hans": "zh_CN", "zh-Hant": "zh_TW" } as const;
export type LocaleTag = keyof typeof sources;

const pluginRoot = join(import.meta.dir, "..");
const repoRoot = join(pluginRoot, "..", "..");

type ChromeMessages = Record<string, { message: string; placeholders?: Record<string, { content: string }> }>;

/** Chrome's named placeholders ($INFORMATION$) become their content ($1). */
function flatten(messages: ChromeMessages): Record<string, string> {
    const flat: Record<string, string> = {};
    for (const [key, entry] of Object.entries(messages)) {
        let text = entry.message;
        for (const [name, placeholder] of Object.entries(entry.placeholders ?? {})) {
            text = text.replace(new RegExp(`\\$${name}\\$`, "gi"), placeholder.content);
        }
        flat[key] = text;
    }
    return flat;
}

export function buildLocale(tag: LocaleTag): Record<string, string> {
    const chrome = flatten(JSON.parse(readFileSync(join(repoRoot, "src", "_locales", sources[tag], "messages.json"), "utf8")));
    const extra: Record<string, string> = JSON.parse(readFileSync(join(pluginRoot, "messages", `${tag}.json`), "utf8"));
    for (const key of Object.keys(extra)) {
        if (key in chrome) throw new Error(`messages/${tag}.json redefines ${key} from src/_locales`);
    }
    const merged = { ...chrome, ...extra };
    return Object.fromEntries(Object.keys(merged).sort().map((key) => [key, merged[key]!]));
}

export const localeFile = (tag: LocaleTag) => join(pluginRoot, "locales", `${tag}.json`);
export const render = (table: Record<string, string>) => `${JSON.stringify(table, null, 4)}\n`;

if (import.meta.main) {
    for (const tag of Object.keys(sources) as LocaleTag[]) {
        writeFileSync(localeFile(tag), render(buildLocale(tag)));
        console.log(`wrote locales/${tag}.json`);
    }
}
