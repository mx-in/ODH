/** `baron create <name> --template action|lookup|webview|settings`: a new plugin folder ready for `baron dev`. */
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";

export const templates = ["action", "lookup", "webview", "settings"] as const;
export type Template = (typeof templates)[number];

/** The workspace's packages, linked with file: paths until they're published on npm. */
const packages = resolve(import.meta.dir, "..", "..");

export function createPlugin(name: string, template: Template, parent = "."): string {
    if (!/^[a-z][a-z0-9-]*$/.test(name)) throw new Error("Use lowercase letters, digits and hyphens for the name, such as my-plugin");
    const folder = resolve(parent, name);
    if (existsSync(folder)) throw new Error(`${folder} already exists`);
    const title = name.split("-").map((w) => w[0]!.toUpperCase() + w.slice(1)).join(" ");
    const id = `org.example.${name}`;
    const files = templateFiles(template, { id, title, name });
    const link = (pkg: string) => `file:${relative(folder, join(packages, pkg))}`;
    files["package.json"] = json({
        name, version: "1.0.0", private: true, type: "module",
        scripts: { build: "baron build", dev: "baron dev", test: "baron test", pack: "baron pack" },
        devDependencies: { "@baron/api": link("api"), "@baron/cli": link("cli"), "@baron/test": link("test"), "@types/bun": "1.4.2", typescript: "7.0.2" },
    });
    files["tsconfig.json"] = json({
        compilerOptions: { target: "ES2023", lib: ["ES2023"], module: "ESNext", moduleResolution: "bundler", strict: true, noEmit: true,
                           allowImportingTsExtensions: true, skipLibCheck: true, types: ["bun"] },
        include: ["src", "test"],
    });
    files[".gitignore"] = "node_modules/\ndist/\n";
    for (const [path, content] of Object.entries(files)) {
        mkdirSync(join(folder, path, ".."), { recursive: true });
        writeFileSync(join(folder, path), content);
    }
    return folder;
}

const json = (value: unknown) => `${JSON.stringify(value, null, 4)}\n`;

function templateFiles(template: Template, { id, title }: { id: string; title: string; name: string }): Record<string, string> {
    const manifest = (extra: Record<string, unknown>) => json({
        $schema: "./node_modules/@baron/api/schema/manifest-1.json", id, name: title, description: `${title}: a Baron plugin.`,
        version: "1.0.0", apiVersion: 1, main: "dist/main.js", ...extra,
    });
    const harness = `import { afterEach, expect, test } from "bun:test";\nimport { join } from "node:path";\nimport { createHarness, type Harness } from "@baron/test";\n\nlet h: Harness | undefined;\nafterEach(() => h?.close());\n`;
    switch (template) {
        case "action":
            return {
                "manifest.json": manifest({ permissions: ["selection.replace"], actions: [{ id: "transform", title, when: { editable: true } }] }),
                "src/main.ts": `import { definePlugin } from "@baron/api";\n\nexport default definePlugin({\n    actions: {\n        transform: (context) => ({ type: "replace", text: context.text.toUpperCase() }),\n    },\n});\n`,
                "test/main.test.ts": `${harness}\ntest("replaces the selection", async () => {\n    h = await createHarness({ plugin: join(import.meta.dir, "..") });\n    expect(await h.runAction("transform", { text: "fox", editable: true })).toEqual({ type: "replace", text: "FOX" });\n});\n`,
            };
        case "lookup":
            return {
                "manifest.json": manifest({ permissions: ["network:dict.example"], actions: [{ id: "lookup", title, when: { contentTypes: ["word"] } }] }),
                "src/main.ts": `import { definePlugin } from "@baron/api";\n\nexport default definePlugin({\n    actions: {\n        async lookup(context) {\n            const response = await fetch(\`https://dict.example/word/\${encodeURIComponent(context.text)}\`);\n            return { type: "toast", message: response.ok ? await response.text() : "No definition found." };\n        },\n    },\n});\n`,
                "test/main.test.ts": `${harness}\ntest("shows the definition", async () => {\n    h = await createHarness({ plugin: join(import.meta.dir, "..") });\n    h.http.mock("https://dict.example/word/fox", { body: "a small wild dog" });\n    expect(await h.runAction("lookup", { text: "fox" })).toEqual({ type: "toast", message: "a small wild dog" });\n});\n`,
            };
        case "webview":
            return {
                "manifest.json": manifest({ actions: [{ id: "show", title }] }),
                "src/main.ts": `import { definePlugin } from "@baron/api";\n\nexport default definePlugin({\n    actions: {\n        async show(context, host) {\n            // The page gets data as baron.view.data; messages go both ways while the panel is open.\n            const view = await host.ui.openWebView("views/panel.html", { data: { text: context.text }, height: 120 });\n            view.onMessage((message) => {\n                if ((message as { shout?: boolean }).shout) void view.postMessage({ text: context.text.toUpperCase() });\n            });\n        },\n    },\n});\n`,
                "views/panel.html": `<!doctype html>\n<html>\n<head>\n    <meta charset="utf-8">\n    <link rel="stylesheet" href="panel.css">\n    <!-- Scripts load only from the package; inline scripts and event attributes don't run. -->\n    <script src="panel.js" defer></script>\n</head>\n<body>\n    <p id="text"></p>\n    <button id="shout">Shout</button>\n</body>\n</html>\n`,
                "views/panel.css": `/* Baron's colours: --baron-background, --baron-text, --baron-accent and more, for light and dark. */\nbody { margin: 12px; }\n#text { font-size: 18px; }\nbutton { color: var(--baron-accent); }\n`,
                "views/panel.js": `// window.baron: the host API (baron.http, baron.storage, …) and baron.view for this panel.\nconst text = document.getElementById("text");\ntext.textContent = baron.view.data.text;\nbaron.view.onMessage((message) => { text.textContent = message.text; });\ndocument.getElementById("shout").addEventListener("click", () => baron.view.postMessage({ shout: true }));\nbaron.view.resize(document.body.scrollHeight + 24);\n`,
                "test/main.test.ts": `${harness}\ntest("opens the panel and answers the page", async () => {\n    h = await createHarness({ plugin: join(import.meta.dir, "..") });\n    await h.runAction("show", { text: "fox" });\n    const [view] = h.views.opened;\n    expect(view).toMatchObject({ path: "views/panel.html", data: { text: "fox" } });\n    h.views.send(view!.id, { shout: true });\n    await Bun.sleep(20);\n    expect(view!.messages).toEqual([{ text: "FOX" }]);\n});\n`,
            };
        case "settings":
            return {
                "manifest.json": manifest({
                    preferences: [
                        { id: "greeting", type: "text", title: "Greeting", default: "Hello" },
                        { id: "times", type: "number", title: "Times", min: 1, max: 5, default: 1 },
                        { id: "shout", type: "checkbox", title: "Shout", label: "Use capitals", default: false },
                        { id: "style", type: "dropdown", title: "Style", optionsFrom: "styles" },
                        { id: "check", type: "button", title: "", label: "Check settings", run: "check" },
                    ],
                    actions: [{ id: "greet", title }],
                }),
                "src/main.ts": `import { definePlugin } from "@baron/api";\n\nexport default definePlugin({\n    actions: {\n        greet(context, host) {\n            const text = \`\${host.preferences["greeting"]}, \${context.text}! \`.repeat(Number(host.preferences["times"] ?? 1)).trim();\n            return { type: "toast", message: host.preferences["shout"] ? text.toUpperCase() : text };\n        },\n    },\n    options: {\n        styles: () => [{ value: "plain", title: "Plain" }, { value: "fancy", title: "Fancy" }],\n    },\n    buttons: {\n        check: (preferences) => ({ message: \`Greeting is "\${preferences["greeting"]}"\`, kind: "success" }),\n    },\n});\n`,
                "test/main.test.ts": `${harness}\ntest("greets with the preferences", async () => {\n    h = await createHarness({ plugin: join(import.meta.dir, ".."), preferences: { shout: true } });\n    expect(await h.runAction("greet", { text: "fox" })).toEqual({ type: "toast", message: "HELLO, FOX!" });\n    expect(await h.runOptions("styles")).toHaveLength(2);\n});\n`,
            };
    }
}
