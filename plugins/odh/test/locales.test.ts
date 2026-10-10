import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { buildLocale, localeFile, render, sources, type LocaleTag } from "../scripts/locales.ts";

for (const tag of Object.keys(sources) as LocaleTag[]) {
    test(`locales/${tag}.json matches src/_locales and messages/ (run npm run locales -w plugins/odh)`, () => {
        expect(readFileSync(localeFile(tag), "utf8")).toBe(render(buildLocale(tag)));
    });
}

test("placeholders become their content", () => {
    expect(buildLocale("en")["msgSuccess"]).toBe("Connected:$1");
});

test("every language has the same keys", () => {
    const keys = (tag: LocaleTag) => Object.keys(buildLocale(tag)).sort();
    expect(keys("zh-Hans")).toEqual(keys("en"));
    expect(keys("zh-Hant")).toEqual(keys("en"));
});
