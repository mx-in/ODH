# Baron: Selection Popup App — Technical Design

2026-10-09 · mx_in · First written as a [Claude Doc](https://claude.ai/code/artifact/a302bd64-f80d-4be1-875e-414221f4b8d6); this file is the maintained copy, and only it has the UML diagrams

Baron is a standalone macOS app, written in Swift. It shows a small action bar whenever text is selected in any app. Every action beyond the built-ins is a plugin written in TypeScript or JavaScript, so the same plugins can run on a later Windows or Linux host. ODH dictionary lookup with Anki export is the first plugin, not part of the core app.

## Research: what can be captured

Yes: the app, window, page URL, sentence and paragraph can all be read wherever the app supports macOS Accessibility. PopClip itself only gives plugins the text, app and browser URL/title. It has no sentence or paragraph field ([popclip.d.ts](https://www.popclip.app/dev/popclip.d.ts), `interface Context`). We can do better because the needed macOS APIs are public.

| Field | How macOS gives it | Where it works | PopClip exposes it |
| --- | --- | --- | --- |
| Selected text | `AXSelectedText` on the focused element; else Edit › Copy; else simulated ⌘C | Every app (the copy steps cover the rest) | Yes |
| Rich text (HTML, RTF) | Pasteboard flavours after a copy; `AXAttributedStringForRange` | Apps that put HTML or RTF on the clipboard | Yes, opt-in |
| App name, bundle ID, PID | `NSWorkspace.frontmostApplication` | Every app | Yes |
| Window title, document file | `AXTitle`, `AXDocument` on the focused window | Most document-based apps | No |
| Page URL and title | `AXURL` on the page's `AXWebArea`; AppleScript as fallback | Chrome, Edge, Arc, Brave, Safari | Yes |
| Sentence | Web pages: `AXSentenceTextMarkerRangeForTextMarker`. Native text: read about 2,000 characters around `AXSelectedTextRange` with `AXStringForRange`, then split with `NLTokenizer(unit: .sentence)` | Browsers, WebKit views, Cocoa text views | No |
| Paragraph | Web pages: `AXParagraphTextMarkerRangeForTextMarker`. Native text: same window, expanded to the nearest line breaks | Same as sentence | No |
| Selection position on screen | `AXBoundsForRange` or `AXBoundsForTextMarkerRange`; else the mouse position | Accessibility-enabled apps | Internal only |
| Editable or not | Role (`AXTextArea`, `AXTextField`) and whether `AXSelectedText` is settable | Accessibility-enabled apps | Partly (`canPaste`, `canCut`) |

What the evidence shows:

- **The web sentence and paragraph APIs are public.** They are declared in the macOS 26.1 SDK header `AXWebConstants.h`. Chromium implements both in [browser_accessibility_cocoa.mm](https://source.chromium.org/chromium/chromium/src/+/main:ui/accessibility/platform/browser_accessibility_cocoa.mm). WebKit ships layout tests for both ([paragraph](https://github.com/WebKit/WebKit/blob/main/LayoutTests/accessibility/mac/paragraph-text-marker-range-mixed-content-expected.txt), [sentence](https://github.com/WebKit/WebKit/blob/main/LayoutTests/accessibility/mac/sentence-text-marker-range-across-inline-boundary-expected.txt)).
- **Chrome exposes the page URL without AppleScript.** Its `accessibilityURL` returns the tab's URL on the web area ([ax_platform_node_cocoa.mm](https://source.chromium.org/chromium/chromium/src/+/main:ui/accessibility/platform/ax_platform_node_cocoa.mm)). AppleScript stays a fallback, because it needs the user's Automation permission.
- **Chrome and Electron must be told to switch accessibility on.** Chrome turns on its basic accessibility tree when a client reads the app's `AXRole` ([chrome_browser_application_mac.mm](https://source.chromium.org/chromium/chromium/src/+/main:chrome/browser/chrome_browser_application_mac.mm)). Electron apps (VS Code, Slack, Obsidian) need `AXManualAccessibility = true` on the app element ([Electron docs](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md)).
- **Copy-only apps give text and nothing else.** When text only arrives through ⌘C (some Java, game-engine or custom-drawn apps), there is no sentence, paragraph or position. The context fields stay empty and plugins must handle that.
- **Measured on 2026-10-10.** 8 of 13 test apps pass every field, including sentence and paragraph; see [ax-coverage.md](research/ax-coverage.md). Chromium needed a fallback: its sentence and paragraph markers stop at inline elements, so Baron rebuilds the paragraph from the Accessibility tree.

## Goals and non-goals

v1 is a dependable selection bar plus a plugin system; everything else is a plugin or comes later.

**Goals**

1. Show the bar within 150 ms of a mouse selection, double-click, or ⇧-arrow / ⌘A selection, in any app.
2. Offer a global hotkey that runs the same pipeline when automatic popup is off or unreliable.
3. Hand every action one `SelectionContext`: text, app, window, page URL, sentence, paragraph, position, and whether the text is editable.
4. Run actions written in TypeScript or JavaScript, with no Swift in any plugin.
5. Keep the plugin API free of macOS-only ideas, so a later Windows or Linux host runs the same plugins unchanged.
6. Ship ODH dictionary lookup with Anki export as the first plugin.
7. Pass a fixed test list of apps: Safari, Chrome, Arc, Mail, Notes, TextEdit, Pages, Preview, Xcode, VS Code, Slack, Obsidian, Terminal.

**Non-goals for v1**

- Running PopClip's own extensions. [PappuClip](https://github.com/anandghegde/PappuClip) shows this is a project in itself.
- Windows and Linux hosts. They are designed for here, not built.
- Clipboard history, AI chat windows, OCR. Each can be a plugin later.
- A hosted plugin store. v1 installs plugins from a folder or a URL.
- Mac App Store distribution. v1 ships as a Developer ID–signed, notarized download.

## Architecture

Plugins reach the selection and the system only through the host API.

```mermaid
flowchart TB
  src["Source app (any app)<br/>keeps focus and its selection"]
  subgraph main["Main app · Swift · not sandboxed"]
    mon["Selection monitor<br/>mouse-up, double-click, ⇧-arrow, hotkey"]
    gate["Gate<br/>skips secure fields, excluded apps, window drags"]
    ret["Text retriever<br/>AX text → AX web → Edit › Copy → ⌘C"]
    ctx["Context builder<br/>app, window, page URL, sentence, paragraph"]
    bar["Action bar<br/>non-activating panel; shows matching actions"]
    host["Host API<br/>permission checks · http allowlist · clipboard · storage · secrets · text.segment"]
    mon --> gate --> ret --> ctx --> bar --> host
  end
  subgraph plugins["Plugins · TS or JS"]
    man["manifest.json<br/>actions, rules, permissions, preferences"]
    act["Action runtime<br/>JavaScriptCore (macOS) / QuickJS-NG<br/>sandboxed helper process"]
    view["View runtime<br/>native: JSON render tree → SwiftUI<br/>web: WKWebView, e.g. ODH popup"]
  end
  net["Network<br/>dictionary sites, AnkiConnect 127.0.0.1:8765"]
  src -- "events, AX reads" --> mon
  bar --> man
  host <--> act
  host <--> view
  host -- "fetch, allowlisted hosts only" --> net
```

The main app owns everything that touches macOS. Plugins see only the `SelectionContext` and the host API, which is the part rewritten per OS later.

## Selection detection and text retrieval

A selection goes through three stages: a trigger fires, a gate rejects non-text cases, then a fallback chain reads the text. Easydict and OpenClip both use this structure.

**Triggers**

- Mouse: an `NSEvent` global monitor for mouse down, drag and up. Fire on mouse-up after a drag of 5 px or more, on double- and triple-click, and on ⇧-click.
- Keyboard: fire 300 ms after the last ⇧-arrow or ⌘A. Global key monitoring needs the Accessibility permission, which we already ask for.
- Hotkey: one configurable shortcut, recorded with [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT). It skips the gate and goes straight to retrieval.

**Gate (cheap checks before any read)**

- The app is not on the exclusion list: password managers, remote desktops, games, and our own app.
- The focused element is not a secure text field, and secure keyboard input is off (`IsSecureEventInputEnabled()`).
- The focused element's role can hold text. Buttons, menus and scroll bars are rejected.
- The window under the pointer did not move or resize between mouse-down and mouse-up. That would be a window drag, not a selection.

**Retrieval chain (first non-empty result wins)**

1. Accessibility, native text: focused app, then its focused element, then `AXSelectedText`. Every AX call gets a 0.5 s messaging timeout, so a hung app cannot freeze us.
2. Accessibility, web page: `AXSelectedTextMarkerRange`, then `AXStringForTextMarkerRange`. Inside a web page, retry up to 6 times over 300 ms, because Chrome builds its tree lazily; elsewhere, try once and move on.
3. Menu copy: press the app's Edit › Copy menu item through Accessibility. No keystroke is sent, so there is no beep.
4. Keyboard copy: post ⌘C, then wait up to 300 ms for the clipboard to change.

Steps 3 and 4 save every clipboard item first and restore it afterwards. The copy itself is written by the source app, so Baron can't mark it as transient; a clipboard manager may record it. Step 4 posts ⌘C directly: SelectedTextKit's own shortcut strategy scripts System Events and stalls on an Automation prompt. A per-app rule can start the chain at a later step for apps with broken Accessibility.

**Library choice.** Use [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) (MIT) for steps 1–4, behind our own `TextRetriever` protocol so it can be swapped. Easydict (14.9k stars) uses it in production. The gate and the window-drag check are ours. We take ideas, not code, from OpenClip's [text-selection design](https://github.com/ganeshmshetty/openclip/blob/main/docs/architecture/text-selection.md), because OpenClip is AGPL-3.0.

**The bar itself** is a non-activating `NSPanel`, so the source app keeps focus and its selection. It sits above the selection's bounds, or below them near the top of the screen. It closes on a click elsewhere, a key press, scrolling or an app switch.

**Permissions.** Accessibility is required. Automation (per browser) is asked for only if the AppleScript fallback is ever used. macOS ties the Accessibility grant to the code signature, so development builds use one stable signing certificate. Otherwise every rebuild loses the permission, as [PappuClip notes](https://github.com/anandghegde/PappuClip#why-a-signing-certificate).

## Context capture

Context is read in the background right after the text, within a 200 ms budget, and only when an enabled plugin has the matching permission. The bar does not wait for it. An action that needs context waits at most 300 ms more, then runs with whatever arrived.

Context must be read before the user clicks anything. The bar is non-activating, so the source app keeps its focus and selection, but scrolling or typing would change them.

**How each field is read**

- **App:** `NSWorkspace.frontmostApplication` gives the bundle ID, name and PID.
- **Window:** the app's `AXFocusedWindow`, then `AXTitle` and `AXDocument` (a file URL for document apps).
- **Page:** walk `AXParent` up from the focused element to the first `AXWebArea`, then read `AXURL` and `AXTitle`. If that fails and the user has allowed it, ask Safari or the Chrome family through AppleScript.
- **Sentence and paragraph on web pages:** the method depends on the engine, because each breaks a different way ([measurements](research/ax-coverage.md)). Chromium marks its elements with `ChromeAXNodeId`; WebKit doesn't.
    - **WebKit (Safari, Mail):** take the start and end markers of `AXSelectedTextMarkerRange`, ask for `AXSentenceTextMarkerRangeForTextMarker` (or `AXParagraph…`) at each, join the two ranges, then read `AXStringForTextMarkerRange`. A triple-click selection includes trailing line breaks, so its end marker sits in the next paragraph; step back over those breaks with `AXPreviousTextMarkerForTextMarker` first. Don't rebuild from the tree here: WebKit's tree hides `<br>` breaks, so lines would run together.
    - **Chromium (Chrome, Arc, Edge, Electron):** markers stop at inline elements (a word in a `<span>` returns only itself) and pull in neighbouring blocks at block edges. Instead, find the text element under the first selected character (`AXUIElementForTextMarker` after `AXNextTextMarkerForTextMarker`), walk up to the nearest ancestor that isn't inline text or a link, and join its `AXStaticText` values in order. That is the paragraph; the sentence is cut from it with `NLTokenizer`. Markers are the fallback.
    - **Bounds:** `AXBoundsForTextMarkerRange`, or in Chromium, which returns none, the frame of the text element under the selection.
- **Sentence and paragraph in native text:** read `AXSelectedTextRange`, then fetch only about 1,000 characters on each side with `AXStringForRange`. Never read `AXValue` whole, because documents can be megabytes. The paragraph is that slice cut at the nearest line breaks; a selection's trailing line breaks (a triple-click) are ignored when expanding, or the next paragraph would be pulled in. The sentence comes from `NLTokenizer(unit: .sentence)` over the paragraph, which also handles Chinese and Japanese punctuation.
- **Waking apps that build their tree on demand:** Chrome builds a basic tree once `AXRole` is read on the app element. Electron apps need `AXManualAccessibility = true`. iWork apps (Pages, Numbers, Keynote) expose their document text only after `AXEnhancedUserInterface = true`, even though the call reports an error; Baron sets it for those apps only (see Risks).
- **Apps without readable text:** VS Code exposes no editor text unless its "screen reader optimized" mode (`editor.accessibilitySupport`) is on, so Baron gets VS Code text through the copy steps, without context. PDFs in Preview expose one `AXStaticText` per text block; Baron doesn't read context from those blocks yet (planned for task-009).
- **Copy fallback:** text only. All context fields stay `undefined`, and `source` says `"menu-copy"` or `"key-copy"`.

The paragraph is capped at 4,000 characters and the sentence at 1,000; a `truncated` flag says when a cap was hit. Offsets are UTF-16 code units. That is what `CFRange` uses and what JavaScript string indices use, so plugins can slice without converting.

**The contract plugins receive**

```ts
interface SelectionContext {
  text: string;                    // the selection, plain text
  html?: string;                   // only when the app supplied HTML
  source: "ax-text" | "ax-web" | "menu-copy" | "key-copy" | "hotkey";
  editable: boolean;               // can a result replace the selection
  app: { id: string; name: string; pid: number };   // id = bundle ID on macOS
  window?: { title?: string; documentUrl?: string };
  page?: { url: string; title?: string };
  sentence?: TextSpan;             // needs the "context.sentence" permission
  paragraph?: TextSpan;            // needs the "context.paragraph" permission
  bounds?: { x: number; y: number; width: number; height: number };   // screen points
  platform: "macos" | "windows" | "linux";
}

interface TextSpan {
  text: string;
  selectionStart: number;          // UTF-16 offset of the selection inside text
  selectionEnd: number;
  truncated: boolean;
}
```

**What v1 guarantees** (decided 2026-10-10 from the [coverage measurements](research/ax-coverage.md)):

| Field | v1 promise | Basis |
| --- | --- | --- |
| `text`, `source`, `app`, `platform` | Always present | Every measured app, including copy-only reads |
| `editable` | Always present, best effort | Derived from the focused element's role |
| `window.title` | Present when the app has a focused window | All 9 measured apps |
| `bounds` | Usually present; the bar falls back to the pointer | All 8 apps passing every field |
| `sentence`, `paragraph` | **Optional.** Present when Accessibility exposes the text | All 8 apps passing every field; missing in VS Code (default settings), Preview and copy-only apps |
| `page` | **Optional.** Present on web pages | Safari, Chrome, Arc, Mail |
| `window.documentUrl` | **Optional.** Present for document-based apps | TextEdit, Xcode, Terminal, Chrome |
| `html` | **Optional.** Only when the app put HTML on the clipboard | Not measured yet |

Plugins must treat every optional field as absent-able and still work with `text` alone. The shape of `SelectionContext` above stays unchanged.

## Plugin system

A plugin is a folder with a JSON manifest and one JavaScript bundle. Its code runs in a small embedded JavaScript engine inside a sandboxed helper process, and only ever talks to one versioned `host` object, the cross-platform contract. Plugins keep data through host-backed storage and secrets, and show UI in three tiers: settings generated from the manifest, native views built with React, and web views. The choices below come from the [plugin runtime research](research/plugin-runtime.md), which compares Raycast, PopClip, VS Code, Obsidian, Figma and Zed.

> **Detailed design:** [Baron Plugin Platform](design/plugin-platform/README.md) designs each part (manifest, runtime, host API, permissions, storage, settings, web views, native views, tooling, install) on its own, with ODH as the success test. This section is the summary written before it. Where they differ, the platform design is current: the runtime starts in-process and moves into the sandboxed helper in task-011, storage uses SQLite, pages load from `baron-plugin://`, Bun replaces esbuild, `definePlugin` replaces `defineActions`, and `host.text.segment` is asynchronous.

**Package layout**

```text
odh-dictionary/
  manifest.json
  dist/main.js        # ES module, bundled, no external imports
  views/popup.html    # optional web view
  icon.svg
```

**Manifest**

```json
{
  "id": "org.odh.dictionary",
  "name": "ODH Dictionary",
  "version": "1.0.0",
  "apiVersion": 1,
  "main": "dist/main.js",
  "permissions": ["context.sentence", "context.page", "network:dict.youdao.com", "network:127.0.0.1:8765", "storage", "secrets"],
  "preferences": [
    { "id": "deck", "type": "text", "title": "Anki deck", "default": "Default", "required": true },
    { "id": "dictionary", "type": "dropdown", "title": "Dictionary", "default": "collins",
      "options": [{ "value": "collins", "title": "Collins" }, { "value": "cambridge", "title": "Cambridge" }] },
    { "id": "maxExamples", "type": "number", "title": "Examples to show", "default": 2 },
    { "id": "apiKey", "type": "secret", "title": "API key" }
  ],
  "settingsView": "SettingsView",
  "actions": [
    {
      "id": "lookup",
      "title": "Look up",
      "icon": "icon.svg",
      "when": { "maxLength": 64, "regex": "^\\p{L}[\\p{L}'\\- ]*$" }
    }
  ]
}
```

The `when` rules (length, regex, content type, apps, editable) are checked in Swift, never in JavaScript, so the bar draws in a few milliseconds without loading any plugin. `settingsView` is optional: it names a native view (tier 2 below) for settings the declared preferences can't express.

**Preference types.** Baron draws these itself in the plugin's settings pane, the way Raycast, VS Code and PopClip do. A `required` preference is asked for before the plugin's first run.

| Type | Control | Stored as |
| --- | --- | --- |
| `text` | Text field | Settings file |
| `number` | Number field with optional `min` / `max` | Settings file |
| `checkbox` | Checkbox with a `label` | Settings file |
| `dropdown` | Pop-up menu of `options` | Settings file |
| `secret` | Secure field | Keychain, never the settings file |
| `file`, `directory` | Open panel | Settings file (path) |
| `app` | App picker | Settings file (bundle ID) |
| `heading` | Section heading, no value | — |

**The API plugins write against**

```ts
import { definePlugin } from "@baron/api";

export default definePlugin({
  actions: {
    async lookup(ctx: SelectionContext, host: Host) {
      await host.ui.openWebView("views/popup.html", {
        data: { word: ctx.text, sentence: ctx.sentence?.text, url: ctx.page?.url },
      });
    },
  },
});

interface Host {
  apiVersion: 1;
  preferences: Readonly<Record<string, string | number | boolean | undefined>>;  // declared values; secrets excluded
  http: { fetch(url: string, init?: RequestInit): Promise<Response> };          // allowed hosts only, no CORS
  clipboard: { readText(): Promise<string>; writeText(text: string): Promise<void> };
  selection: { replace(text: string): Promise<void> };                          // needs "selection.replace"
  storage: {                                                                     // JSON values, per plugin, 5 MB
    get<T>(key: string): Promise<T | undefined>;
    set(key: string, value: unknown): Promise<void>;
    remove(key: string): Promise<void>;
    keys(): Promise<string[]>;
  };
  cache: {                                                                       // strings, LRU, 10 MB, may be evicted
    get(key: string): Promise<string | undefined>;
    set(key: string, value: string): Promise<void>;
    remove(key: string): Promise<void>;
  };
  secrets: {                                                                     // Keychain; needs "secrets"
    get(key: string): Promise<string | undefined>;
    set(key: string, value: string): Promise<void>;
    remove(key: string): Promise<void>;
  };
  text: { segment(text: string, unit: "word" | "sentence"): { start: number; end: number }[] };
  ui: {
    toast(message: string, kind?: "info" | "success" | "error"): void;
    show(view: BaronElement): Promise<ViewHandle>;                               // native view, tier 2
    openWebView(path: string, data?: unknown): Promise<ViewHandle>;              // web view, tier 3
    openSettings(): void;
    openUrl(url: string): Promise<void>;
  };
  log(...args: unknown[]): void;
}
```

`host.text.segment` exists because sentence splitting must not depend on `Intl.Segmenter`, which QuickJS lacks. The host uses `NLTokenizer` on macOS and ICU elsewhere.

**Runtime: a small embedded engine, not Node.** Raycast started on JavaScriptCore and moved to Node because developers wanted npm packages and Node APIs; the cost was a large runtime and no sandbox. Baron keeps the sandbox and answers the npm problem with a fixed web-platform subset.

| Engine | Platforms | Cost to ship | Verdict |
| --- | --- | --- | --- |
| JavaScriptCore | macOS, iOS | None, part of macOS | **macOS.** PopClip and Raycast's first design use it |
| [QuickJS-NG](https://github.com/quickjs-ng/quickjs) | All | 1.3 MB, MIT | **Windows and Linux.** Figma's sandbox engine; run in CI from day one |
| Node | All | 61.8 MB | No: only a process-level sandbox |
| Deno | All | 153.2 MB | No: permissions are per process |
| WebAssembly (Extism, Javy) | All | Small runtime | Later: for plugins in other languages |

- **Web-platform subset**, provided by the host in every context: `fetch` (through `host.http`), `URL`, `URLSearchParams`, `TextEncoder`, `TextDecoder`, `setTimeout` and friends, `AbortController`, `crypto.getRandomValues`, `crypto.subtle.digest`, `structuredClone`, `console`.
- **npm:** `baron build` bundles pure-JavaScript packages with esbuild. Packages that need Node built-ins (`fs`, `child_process`, `net`) are unsupported by design.
- **The API stays inside ES2023 plus `host`.** CI runs every plugin's tests on JavaScriptCore and QuickJS-NG, so a plugin that passes both should work on a future Windows host.

**Process model.** One sandboxed helper process (an XPC service with no file or network entitlement) holds one engine context per plugin, as in Raycast's first design. A crash or runaway loop kills the helper, not Baron; Baron restarts it and disables a plugin after three strikes. Each action call has a 10 s limit, and an idle plugin is unloaded after 60 s. QuickJS can cap each runtime's memory; JavaScriptCore has no public per-context limit, so Baron watches the helper's memory instead.

**Storage.** The host stores everything; plugin code never touches the file system.

| API | Holds | Backed by | Limit | Kept |
| --- | --- | --- | --- | --- |
| `host.preferences` | Declared settings (read-only to the plugin) | Baron's settings file | — | Until the user changes them |
| `host.storage` | Plugin data, JSON values | One file per plugin in Baron's Application Support folder | 5 MB | Until uninstall |
| `host.cache` | Disposable strings | Files with an LRU index | 10 MB | May be evicted at any time |
| `host.secrets` | Tokens and keys, including `secret` preferences | Keychain, one item per plugin and key | — | Until uninstall |

**UI in three tiers**

| Tier | The plugin writes | Baron draws | Use for |
| --- | --- | --- | --- |
| 1. Generated settings | `preferences` in the manifest | A native settings pane | Most settings: no UI code at all |
| 2. Native views | React components from `@baron/ui` | SwiftUI on macOS, WinUI or GTK later | Custom settings (`settingsView`), result lists, details, forms |
| 3. Web views | An HTML page in the package | `WKWebView` (WebView2, WebKitGTK later) | Fully custom UI, such as ODH's popup |

How a native view works:

1. The plugin returns a React element built from `@baron/ui` components: `Form` (`TextField`, `SecureField`, `Checkbox`, `Dropdown`, `NumberField`), `List` (`Item`, `Section`), `Detail` (Markdown plus metadata), `ActionPanel` and `Action`.
2. React runs inside the plugin's engine context with Baron's reconciler, which ships in `@baron/ui`. React needs only timers, which the host provides. React Native ran on JavaScriptCore for years, and React has been run on QuickJS too.
3. Each React commit produces a JSON render tree, sent to Baron. v1 sends the whole tree; JSON Patch diffs, as Raycast uses, come only if trees grow large.
4. Baron maps the tree to SwiftUI views. The tree format is part of the cross-platform contract, so a Windows host maps the same tree to WinUI.
5. User input (typing, toggling, choosing an action) goes back as an event message that calls the plugin's handler, which updates state and triggers the next render.

Views appear in two places: the plugin's tab in Baron's Settings window (generated preferences, then `settingsView` if any) and a result panel next to the action bar. Web views follow the same rules as before: a `plugin://<id>/` URL, a strict Content Security Policy with no direct network, and the same `host` object through a message bridge.

**TypeScript.** Plugins ship compiled JavaScript. Two packages: `@baron/api` (types for `host` and `SelectionContext`, plus `defineActions`) and `@baron/ui` (the components and reconciler). A small CLI (`baron build`, `baron dev`) bundles TypeScript and TSX with esbuild and reloads the plugin on save. The app contains no TypeScript compiler.

**DOM in actions.** The engine context has no DOM. A plugin that scrapes HTML either bundles [linkedom](https://github.com/WebReflection/linkedom) (pure JS, also bundled by PopClip) or does the scraping inside a web view.

**Permissions** are listed in the manifest, shown at install, and enforced by the host on every call.

| Permission | What it unlocks | Prompt |
| --- | --- | --- |
| `context.sentence`, `context.paragraph` | Those context fields | At install |
| `context.page` | Page URL and title | At install |
| `network:<host>` | `host.http.fetch` to that host only | At install |
| `clipboard.read` | `host.clipboard.readText` | At install |
| `selection.replace` | Replacing the selected text | At install |
| `secrets` | `host.secrets` and `secret` preferences | At install |
| `storage` | `host.storage` and `host.cache` | None |

**Versioning.** `apiVersion` is an integer. The host supports the current and the previous version, and refuses newer ones with a clear message. The render-tree format is versioned with it.

**Open questions for the plugin system**

Decided when the user approved the platform design on 2026-10-10; the reasons are in its [Decisions](design/plugin-platform/README.md#decisions) table.

- [x] Accept no Node built-ins (`fs`, `child_process`, `net`) in v1? This keeps the sandbox but rules out some npm packages. Decided: no Node built-ins; Bun is the developer toolchain only.
- [x] Build native views (tier 2) inside task-003, or as their own task after it? Tiers 1 and 3 are enough for the ODH plugin. Decided: their own task after ODH (task-013).
- [x] Are the 5 MB storage and 10 MB cache quotas right? Decided: yes, with 1 MB and 2 MB per value.
- [x] Should secrets sync through iCloud Keychain or stay on this Mac? PopClip lets each secret choose; the proposal is local by default. Decided: this Mac only in v1.

## Cross-platform plan

Share everything a plugin touches; write the host natively per OS. The shared parts are the `host` API typings, the manifest schema, the plugin packages, the conformance tests and the ODH plugin. The selection monitor, the bar window and the engine glue are rewritten per OS, behind the same contract.

| Concern | macOS (v1) | Windows (later) | Linux (later) |
| --- | --- | --- | --- |
| Notice a selection | `NSEvent` global monitors | Low-level mouse and keyboard hooks | X11: input events. Wayland: no global mouse events, so hotkey only |
| Read selected text | `AXSelectedText` | UI Automation `TextPattern.GetSelection` | The PRIMARY selection, which holds the selected text on X11 and Wayland; AT-SPI `Text` |
| Copy fallback | Edit › Copy, then ⌘C | Ctrl+C via `SendInput` | Ctrl+C via XTest (X11 only) |
| Sentence, paragraph | Text markers, `AXStringForRange` | `ExpandToEnclosingUnit(TextUnit_Paragraph)`. There is no sentence unit, so ICU splits the paragraph ([TextUnit](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/ne-uiautomationcore-textunit)) | AT-SPI granularity `SENTENCE` and `PARAGRAPH` ([TextGranularity](https://docs.gtk.org/atspi2/enum.TextGranularity.html)) |
| Page URL | `AXURL` on the web area | To be researched (UIA on the address bar) | To be researched |
| Bar window | Non-activating `NSPanel` | Topmost window with `WS_EX_NOACTIVATE` | X11: override-redirect window. Wayland: absolute placement is not allowed |
| Action engine | JavaScriptCore | QuickJS-NG | QuickJS-NG |
| Native views (tier 2) | SwiftUI | WinUI | GTK |
| Web views (tier 3) | `WKWebView` | WebView2 | WebKitGTK |
| Sentence splitting | `NLTokenizer` | ICU (`icu.dll`, built into Windows 10 1903+) | ICU |

**Rules that keep plugins portable**

- Icons are SVG files or short text labels. SF Symbols names are not allowed in manifests.
- `app.id` is opaque: a bundle ID on macOS, an executable name on Windows, a desktop-file ID on Linux. App rules in manifests can list one ID per platform.
- No API takes a macOS key name. If key presses are added later, they use `mod` for ⌘ or Ctrl.
- `platform` is in the context, so a plugin can adapt. A manifest may also list `platforms` to opt out of one.

Wayland is the weakest target: no global mouse events and no free window placement. On Wayland the product is hotkey-first, with the bar shown near the pointer where the compositor allows it.

## First plugin: ODH dictionary and Anki

The ODH plugin is a view that loads ODH's existing dictionary scripts and popup UI unchanged, with a thin shim from ODH's `api` to `host`. The ODH repository stays the single source of those files. A build step copies them into the plugin package, so the Chrome extension and the plugin share one copy.

| ODH today | In the plugin |
| --- | --- |
| Content script picks the word and its sentence from the page DOM | `ctx.text`, `ctx.sentence.text`, `ctx.page.url` from the host |
| Dictionary scripts in `src/dict/*.js` run in a sandboxed page | The same files run in the plugin's view, which has a real `DOMParser` |
| `api.fetch` goes through the service worker | `api.fetch(url)` becomes `host.http.fetch(url)` then `.text()`; no CORS limits |
| `api.deinflect` uses `src/bg/js/deinflector.js` | The same file and data, bundled into the view |
| `api.locale`, `api.getBuiltin` | `navigator.language`; bundled built-in dictionary data |
| Popup UI from `src/fg/js/frame.js` | The same UI, rendered in the view |
| AnkiConnect calls from `src/bg/js/ankiconnect.js` | The same requests to `127.0.0.1:8765` through `host.http.fetch` |

The manifest lists the hosts of the built-in dictionaries plus `127.0.0.1:8765` for AnkiConnect. Dictionary scripts that users add from a URL could contact any host; how to grant that is an open question below.

**Apple Dictionary, later.** Plugins cannot call macOS APIs, so the system dictionary would be an optional host capability: `host.system.dictionary?.lookup(word)`. It returns HTML on macOS and is `undefined` elsewhere. PopClip offers the plain-text version as `util.getDictionaryDefinition`.

## Security and privacy

The app sees everything a user selects, so the default is that nothing leaves the Mac and plugins get only what they declared.

- **No telemetry.** Selected text and context leave the machine only when a plugin with a `network:` permission sends them.
- **Plugins run in a sandboxed helper process.** The main app cannot be sandboxed, because it needs Accessibility. The helper is sandboxed, with no file access and no network entitlement. Every network call goes through the host, which checks the allowlist first.
- **Views are locked down.** The Content Security Policy blocks direct network access and navigation outside `plugin://<id>/`. Links open through `host.ui.openUrl`.
- **Sensitive places never trigger.** Secure text fields, secure keyboard input, and default-excluded apps (1Password, Bitwarden, Keychain Access) are skipped before any read.
- **The clipboard is put back.** The copy fallback restores the user's clipboard and marks its own write as transient.
- **Permissions are shown at install** and shown again when an update adds any.
- **Logs never contain selected text.** Log the text length and the strategy used, never the content.
- **v1 plugins are unsigned.** Installing from a folder or URL shows the source and a warning. Signed packages come later.

## Milestones

v1 ships after five milestones, each closed by a gate.

```mermaid
flowchart TB
  m0["M0 · Spike<br/>Measure AX text, context and copy fallback on the 13 test apps;<br/>stable signing certificate for dev builds"]
  m1["M1 · Selection bar<br/>Monitor, gate, retriever, non-activating bar;<br/>built-ins: copy, search, open link"]
  m2["M2 · Plugin runtime<br/>Manifest, JavaScriptCore helper, host API, permissions;<br/>CLI: baron build, baron dev"]
  m3["M3 · Context and views<br/>Sentence, paragraph, window and page URL;<br/>WKWebView views with the host bridge"]
  m4["M4 · ODH plugin<br/>ODH dictionary scripts and popup in a view;<br/>Anki export through AnkiConnect"]
  v1["v1 release<br/>Developer ID–signed, notarized download"]
  m0 -- "gate: coverage table reviewed; context fields confirmed" --> m1
  m1 -- "gate: bar shows in every test app, or the gap is documented" --> m2
  m2 -- "gate: sample plugins pass on JavaScriptCore and QuickJS-NG" --> m3
  m3 -- "gate: a plugin reads the sentence in Safari, Chrome, Mail, Notes" --> m4
  m4 -- "gate: look up a word and add a card from Chrome, Mail, Slack" --> v1
```

Each milestone ends at a gate, not a date; no schedule has been set yet. M0 matters most: its coverage table decides which context fields v1 promises to plugins.

M2 to M4 are built as tasks 004 to 012, one per platform sub-project, in the order set by the [platform design](design/plugin-platform/README.md#build-order). Native views follow as task-013 and the release as task-014 ([task backlog](tasks.md)).

## Risks and open questions

The biggest risk is uneven Accessibility support across apps. Milestone 0 measures it before any API is frozen.

| Risk | Effect | Mitigation |
| --- | --- | --- |
| Accessibility support varies (Electron, Java, Qt, games) | No context, or no text without copying | Copy fallback, per-app rules, measured in M0 |
| Switching on Chrome or Electron accessibility costs them CPU and memory | Users blame us for slower apps | Switch it on only for the frontmost app, and only when a context permission is in use |
| `AXEnhancedUserInterface` (needed for Pages, Numbers, Keynote) slows those apps' window animations and can confuse window managers | iWork feels sluggish while Baron runs | Set it only for iWork apps; measure the effect; consider setting it only while a selection is being read, then clearing it |
| False triggers (Finder drags, drawing apps) | The bar becomes annoying | Gate, exclusion list, optional hold-a-modifier mode |
| Copy fallback side effects | Clipboard managers record junk; apps run copy hooks | Full restore, menu copy before ⌘C. The source app writes the copy, so it can't be marked transient |
| macOS changes AX behaviour or permission prompts | Breakage after an OS update | Test on each macOS beta; keep the retriever swappable |
| The plugin API is hard to change once published | Stuck with early mistakes | Small v1 surface, `apiVersion`, support N and N−1 |
| JavaScriptCore and QuickJS-NG behave differently | A plugin works on macOS only | Every plugin's tests run on both engines in CI |
| No Node APIs in plugins | Developers can't use some npm packages, the reason Raycast moved to Node | A documented web-platform subset; pure-JS npm packages bundle fine; revisit with real plugin requests |
| React in every plugin context costs parse time and memory | Slow first view, larger helper | Load `@baron/ui` only when a plugin shows a native view; QuickJS bytecode precompile |

**Open questions**

- [x] Product name: **baron** (package scope `@baron`, CLI `baron`). Decided 2026-10-10.
- [ ] Windows host language: C# with WinUI, or Rust?
- [ ] Network access for dictionary scripts users add from a URL: a broad `network:*` grant with a warning, or a prompt for each new host?
- [ ] Should the bar appear automatically by default, or only while a modifier key is held?
- [x] Minimum macOS version: 14. Decided 2026-10-10.
- [x] Licence: MIT, like ODH. No GPL or AGPL code is copied from Easydict, OpenClip or Selected. Decided 2026-10-10.

## UML: the selection bar as built

Drawn from the code at the end of task-005 (`macos/Sources`): the selection bar of tasks 001 and 002, now offering plugin actions. Pure logic lives in `BaronCore`, which has unit tests; anything that touches Accessibility, events or windows lives in `BaronPlatform`; the app target wires them together.

```mermaid
classDiagram
  namespace Baron_app {
    class SelectionCoordinator {
      +onRun: (Trigger, PipelineOutcome, source)
      +apply(BaronSettings)
      +start()
      +stop()
      +onPluginAction: (Entry, SelectionRun)
      -handle(Trigger)
      -perform(BarItem)
    }
    class PluginController {
      +runtime: PluginRuntime
      +catalog: PluginActionCatalog
      +reload() scans the development folder
      +run(entry, selection) Result
    }
    class ToastPresenter {
      +show(message, kind)
    }
  }
  namespace BaronPlatform {
    class SelectionEventMonitor {
      +onTrigger: (Trigger)
      +start()
      +stop()
    }
    class HotkeyMonitor {
      +onTrigger: (Trigger)
      +setEnabled(Bool)
    }
    class FocusedSelectionSource {
      +app: NSRunningApplication
      +focused: AXElement?
      +current()$ FocusedSelectionSource?
    }
    class ActionBarController {
      +onSelect: (BarItem)
      +show(items, selection, pointer)
      +hide()
    }
    class ActionEffectPerformer {
      +perform(ActionEffect)$
    }
    class AXTextRetriever
    class AXWebRetriever
    class CopyRetriever
    class ToastPanel {
      +show(message, kind, near)
    }
    class SelectionReplacer {
      +replace(with: text)$ AX, else paste
    }
  }
  namespace BaronCore {
    class PointerTriggerDetector
    class KeyboardTriggerDetector
    class Trigger {
      +kind: TriggerKind
      +location: CGPoint
      +windowDragged: Bool
      +skipsGate: Bool
    }
    class SelectionPipeline {
      +gate: Gate
      +retrievalRules: AppRetrievalRules
      +actions: BuiltInActions
      +plugins: PluginActionCatalog
      +isPaused: Bool
      +run(Trigger, SelectionSource) async PipelineOutcome
      +cancel()
    }
    class SelectionSource {
      <<interface>>
      +bundleIdentifier: String?
      +selectionApp: SelectionApp
      +isEditable: Bool
      +gateInput(for: Trigger) GateInput
      +retrievalChain() RetrievalChain
      +selectionBounds(after: RetrievalStep) CGRect?
    }
    class Gate {
      +rules: [GateRule]
      +evaluate(GateInput) GateDecision
    }
    class GateRule {
      <<interface>>
      +reject(GateInput) GateReason?
    }
    class RetrievalChain {
      +retrievers: [TextRetriever]
      +retrieve(startingAt: RetrievalStep) async RetrievalResult?
    }
    class TextRetriever {
      <<interface>>
      +step: RetrievalStep
      +retrieve() async String?
    }
    class AppRetrievalRules {
      +startSteps: [bundle ID: RetrievalStep]
      +startStep(for: bundle ID) RetrievalStep
    }
    class BuiltInActions {
      +actions: [BuiltInAction]
      +items(for: text) [BarItem]
      +effect(of: itemID, for: text) ActionEffect?
    }
    class BuiltInAction {
      <<interface>>
      +item: BarItem
      +applies(to: text) Bool
      +effect(for: text) ActionEffect?
    }
    class BarPlacement {
      +frame(barSize, selection, pointer, visibleFrame)$ CGRect
    }
    class PluginActionCatalog {
      +entries: [Entry]
      +items(for: WhenInput) [BarItem]
      +entry(forItemID) Entry?
    }
    class PluginActionResult {
      <<enumeration>>
      nothing, copy, replace, toast, openURL
      +parse(value, editable, mayReplace)$
    }
    class ExcludedAppRule
    class SecureInputRule
    class TextRoleRule
    class WindowDragRule
    class CopyAction
    class SearchAction
    class OpenLinkAction
  }
  SelectionCoordinator --> SelectionEventMonitor
  SelectionCoordinator --> HotkeyMonitor
  SelectionCoordinator --> SelectionPipeline
  SelectionCoordinator --> ActionBarController
  SelectionCoordinator ..> FocusedSelectionSource : current() per trigger
  SelectionCoordinator ..> ActionEffectPerformer
  SelectionEventMonitor --> PointerTriggerDetector
  SelectionEventMonitor --> KeyboardTriggerDetector
  SelectionEventMonitor ..> Trigger : emits
  HotkeyMonitor ..> Trigger : emits, skips the gate
  SelectionPipeline --> Gate
  SelectionPipeline --> AppRetrievalRules
  SelectionPipeline --> BuiltInActions
  SelectionPipeline ..> SelectionSource
  SelectionSource <|.. FocusedSelectionSource
  FocusedSelectionSource ..> RetrievalChain : builds
  Gate o-- GateRule
  GateRule <|.. ExcludedAppRule
  GateRule <|.. SecureInputRule
  GateRule <|.. TextRoleRule
  GateRule <|.. WindowDragRule
  RetrievalChain o-- TextRetriever
  TextRetriever <|.. AXTextRetriever : ax-text
  TextRetriever <|.. AXWebRetriever : ax-web
  TextRetriever <|.. CopyRetriever : menu-copy, key-copy
  BuiltInActions o-- BuiltInAction
  BuiltInAction <|.. CopyAction
  BuiltInAction <|.. SearchAction
  BuiltInAction <|.. OpenLinkAction
  ActionBarController ..> BarPlacement
  SelectionPipeline --> PluginActionCatalog
  SelectionCoordinator ..> PluginController : plugin buttons
  PluginController ..> PluginActionResult
  PluginController ..> ToastPresenter
  ToastPresenter --> ToastPanel
  ActionEffectPerformer ..> SelectionReplacer : replace
```

From a selection to a performed action:

```mermaid
sequenceDiagram
  actor User
  participant Mon as SelectionEventMonitor
  participant Coord as SelectionCoordinator
  participant Src as FocusedSelectionSource
  participant Pipe as SelectionPipeline
  participant Gate
  participant Chain as RetrievalChain
  participant Bar as ActionBarController
  participant Perf as ActionEffectPerformer
  User->>Mon: drag, double-click, triple-click, shift-click or shift-arrow
  Mon->>Mon: PointerTriggerDetector or KeyboardTriggerDetector (300 ms quiet)
  Mon->>Coord: Trigger
  Coord->>Bar: hide the previous bar
  Coord->>Src: current(): frontmost app and focused element
  Coord->>Pipe: run(trigger, source)
  alt paused, and not the hotkey
    Pipe-->>Coord: paused
  else
    Pipe->>Src: gateInput(for: trigger)
    Pipe->>Gate: evaluate (excluded app, secure input, non-text role, window drag)
    alt rejected
      Gate-->>Pipe: reject(reason)
      Pipe-->>Coord: rejected(reason)
    else passes
      Pipe->>Chain: retrieve(startingAt: per-app start step)
      Chain->>Chain: ax-text, then ax-web (retried in web areas), then menu-copy, then key-copy
      Chain-->>Pipe: text and the step that found it
      Pipe->>Pipe: a newer trigger meanwhile? then superseded
      Pipe->>Src: selectionBounds(after: step)
      Pipe-->>Coord: show(SelectionRun with BuiltInActions items)
      Coord->>Bar: show(items, selection bounds, pointer)
      Bar->>Bar: BarPlacement: above the selection, else below, kept on screen
    end
  end
  Note over Coord: after every run, onRun lets the debug panel probe the context
  alt a built-in action
    User->>Bar: clicks Copy, Search or Open Link
    Bar->>Coord: onSelect(item)
    Coord->>Pipe: actions.effect(of: item, for: text)
    Coord->>Perf: perform(copy or openURL)
  else a plugin action (shown when its when rules match)
    User->>Bar: clicks a plugin's button
    Bar->>Coord: onSelect(item)
    Coord->>Coord: onPluginAction(entry, run)
    Note over Coord: PluginController dispatches with the selection's context (02-runtime, 03-host-api)
    Coord->>Perf: perform the result (copy, replace, openURL) or show a toast, also for errors
  end
```

The context readers. Today only `SelectionProbe` uses them, for `baron-probe`, `baron-uitest` and the debug panel; task-009 builds each action's `SelectionContext` from them.

```mermaid
classDiagram
  class SelectionProbe {
    <<BaronPlatform>>
    +run(on: app, includeCopy) async ProbeReport$
  }
  class AccessibilityWaker {
    +wake(app)$ Electron, Chrome, iWork
  }
  class WindowReader {
    +focusedWindow(of: app)$
    +title(window)$
    +documentURL(window)$
  }
  class WebAreaReader {
    +webArea(containing: element)$
    +url(area)$
    +title(area)$
  }
  class WebSelectionReader {
    +selectedRange(near: element)$ marker range and owner
  }
  class WebContextReader {
    +contextSpan(sentence or paragraph, around: range, in: owner)$ TextSpan?
  }
  class WebTreeContextReader {
    Chromium: paragraph rebuilt from the tree
  }
  class NativeTextWindowReader {
    +window(around: element)$ about 1,000 units each side
  }
  class NativeTextContext {
    <<BaronCore>>
    +paragraph(in: text, selection)$ TextSpan?
    +sentence(paragraph)$ TextSpan?
  }
  class SelectionBoundsReader {
    +bounds(ofNativeSelectionIn: element)$
    +bounds(ofWebSelection: range, in: owner)$
  }
  class TextSpan {
    <<BaronCore>>
    +text: String
    +selectionStart: Int
    +selectionEnd: Int
    +truncated: Bool
  }
  SelectionProbe ..> AccessibilityWaker
  SelectionProbe ..> WindowReader
  SelectionProbe ..> WebAreaReader
  SelectionProbe ..> WebSelectionReader
  SelectionProbe ..> WebContextReader
  SelectionProbe ..> NativeTextWindowReader
  SelectionProbe ..> NativeTextContext
  SelectionProbe ..> SelectionBoundsReader
  WebContextReader ..> WebTreeContextReader : Chromium (ChromeAXNodeId)
  WebContextReader ..> TextSpan
  NativeTextContext ..> TextSpan
```

## Sources

- PopClip: [JavaScript environment](https://www.popclip.app/dev/js-environment), [popclip.d.ts](https://www.popclip.app/dev/popclip.d.ts), [PopClip-Extensions](https://github.com/pilotmoon/PopClip-Extensions)
- Chromium: [browser_accessibility_cocoa.mm](https://source.chromium.org/chromium/chromium/src/+/main:ui/accessibility/platform/browser_accessibility_cocoa.mm), [ax_platform_node_cocoa.mm](https://source.chromium.org/chromium/chromium/src/+/main:ui/accessibility/platform/ax_platform_node_cocoa.mm), [chrome_browser_application_mac.mm](https://source.chromium.org/chromium/chromium/src/+/main:chrome/browser/chrome_browser_application_mac.mm)
- WebKit layout tests: [paragraph text markers](https://github.com/WebKit/WebKit/blob/main/LayoutTests/accessibility/mac/paragraph-text-marker-range-mixed-content-expected.txt), [sentence text markers](https://github.com/WebKit/WebKit/blob/main/LayoutTests/accessibility/mac/sentence-text-marker-range-across-inline-boundary-expected.txt)
- macOS 26.1 SDK headers: `AXWebConstants.h`, `AXAttributeConstants.h` (HIServices framework)
- [Electron accessibility docs](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md) (`AXManualAccessibility`)
- [Easydict](https://github.com/tisfeng/easydict) and [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit)
- [OpenClip](https://github.com/ganeshmshetty/openclip) and its [text-selection design](https://github.com/ganeshmshetty/openclip/blob/main/docs/architecture/text-selection.md) and [JavaScript runtime](https://github.com/ganeshmshetty/openclip/blob/main/docs/runtimes/javascript.md) docs
- [PappuClip](https://github.com/anandghegde/PappuClip), [Selected](https://github.com/sakeven/Selected), [Xpop](https://github.com/DongqiShen/Xpop)
- [QuickJS-NG](https://github.com/quickjs-ng/quickjs), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), [linkedom](https://github.com/WebReflection/linkedom), [sucrase](https://github.com/alangpierce/sucrase)
- Windows [TextUnit enumeration](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/ne-uiautomationcore-textunit); AT-SPI [TextGranularity](https://docs.gtk.org/atspi2/enum.TextGranularity.html)
