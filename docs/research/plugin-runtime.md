# Plugin runtime, storage and UI: research

Researched 2026-10-10 for task-003. Question: what should run Baron's TypeScript/JavaScript plugins, how do plugins store data and secrets, and how do they show UI such as a settings panel? Starting point: [Raycast extensions](https://github.com/raycast/extensions), which give plugins a React library that renders native macOS UI.

**Recommendation:** keep a small embedded engine (JavaScriptCore on macOS, QuickJS-NG elsewhere) in one sandboxed helper process; give plugins host-backed storage, cache, secrets and declared preferences; and offer UI in three tiers: settings generated from the manifest, native views built with React through a Baron renderer, and web views for fully custom UI. Don't bundle Node.

## How Raycast does it

From [How the Raycast API and extensions work](https://www.raycast.com/blog/how-raycast-api-extensions-work) and the [API docs](https://developers.raycast.com):

| Aspect | Raycast |
| --- | --- |
| First design | One XPC extension-host process running many JavaScriptCore engines; UI described as a JSON tree |
| Why they left it | Developers wanted their npm packages and Node APIs; every missing API (sockets, processes, files) had to be polyfilled by hand |
| Current runtime | A bundled Node process; each extension in its own worker thread (V8 isolate) with a heap limit |
| UI | React with a custom reconciler. Each render produces a JSON "render tree"; changes go to Raycast as JSON Patch over JSON-RPC on stdio; Raycast renders its own AppKit components. No web views, on purpose |
| Sandbox | None. They rejected process sandboxing (one Node per extension is expensive; Node and Deno permissions are per process) and note that JavaScriptCore "would have given us a sandbox for free" |
| Settings | Preferences declared in the manifest (`textfield`, `password`, `checkbox`, `dropdown`, `appPicker`, `file`, `directory`); Raycast draws the settings UI; required ones are asked for before first run ([manifest](https://developers.raycast.com/information/manifest), [preferences](https://developers.raycast.com/api-reference/preferences)) |
| Storage | `LocalStorage` key-value, async, not for large data ([storage](https://developers.raycast.com/api-reference/storage)); `Cache` with LRU eviction stored as files ([cache](https://developers.raycast.com/api-reference/cache)); password preferences kept securely |

The lesson for Baron: Raycast's UI model (React → JSON tree → native renderer) is independent of its Node choice; it started on JavaScriptCore. Node bought npm compatibility at the cost of sandboxing and a large runtime.

## Other plugin systems

| System | Runtime | Settings UI | Storage | Custom UI |
| --- | --- | --- | --- | --- |
| [PopClip](https://www.popclip.app/dev/js-environment) | JavaScriptCore, core-js polyfills, bundled libraries (axios, linkedom…) | Options in the manifest (`string`, `boolean`, `multiple`, `password`, `secret`, `heading`); `secret` goes to the Keychain ([popclip.d.ts](https://www.popclip.app/dev/popclip.d.ts)) | Options only | None |
| [VS Code](https://code.visualstudio.com/api/references/contribution-points) | Node extension host | `contributes.configuration` JSON schema, rendered by the Settings editor | `globalState` memento, `SecretStorage` encrypted per platform ([API](https://code.visualstudio.com/api/references/vscode-api)) | Web views |
| [Obsidian](https://github.com/obsidianmd/obsidian-api) | Electron renderer, full DOM | Code: `PluginSettingTab` with a `Setting` builder (`addToggle`, `addText`) | `loadData()` / `saveData()` JSON file | DOM |
| [Figma](https://www.figma.com/blog/an-update-on-plugin-security/) | QuickJS compiled to WebAssembly, after the Realms shim was escaped | Plugin's own iframe | `clientStorage` | iframe UI talking to the sandbox by messages |
| [Zed](https://zed.dev/docs/extensions/developing-extensions) | Rust compiled to WebAssembly (`wasm32-wasip2`) | Settings JSON | — | None |

Patterns that recur: **settings are declared, not drawn** (Raycast, VS Code, PopClip); **secrets go to the platform keychain** (PopClip, VS Code, Raycast); **plugin logic and plugin UI are separated** (Figma's sandbox + iframe, Raycast's worker + native renderer).

## JavaScript engines

| Engine | Size on this Mac | Platforms | Sandbox | Notes |
| --- | --- | --- | --- | --- |
| JavaScriptCore | 0 (part of macOS) | macOS, iOS; Linux via WebKitGTK | Per context, no host APIs unless given | JIT; used by PopClip and Raycast's first design |
| [QuickJS-NG](https://github.com/quickjs-ng/quickjs) | 1.3 MB (`qjs`, arm64) | All | Per runtime | ES2023, interpreter only, bytecode precompile; Figma's sandbox engine |
| [Hermes](https://github.com/facebook/hermes) | Few MB | All | Per runtime | Built for React Native; bytecode ahead of time; weaker for arbitrary npm code |
| Node | 61.8 MB | All | Process level only | npm and Node APIs; Raycast's choice |
| Deno | 153.2 MB | All | Process-level permissions | Embeddable core via Rust |
| WebAssembly ([Extism](https://github.com/extism/extism), [Javy](https://github.com/bytecodealliance/javy)) | Small runtime | All | Strong, per module | Plugins in any language; JS runs as QuickJS inside WASM, slower and bigger |

## Native UI from JavaScript

| Approach | Example | Fit for Baron |
| --- | --- | --- |
| Declarative settings schema | Raycast preferences, VS Code configuration, PopClip options | **Yes.** No plugin UI code; native and consistent; ports to any OS |
| React + custom reconciler → JSON tree → native views | Raycast (AppKit); [react-watchos](https://github.com/emindeniz99/react-watchos) runs React on QuickJS and renders SwiftUI | **Yes.** Works in any engine; React needs only timers; the JSON tree is the cross-platform contract |
| Full React Native for macOS | [react-native-macos](https://github.com/microsoft/react-native-macos) | No: an app framework, heavy for small plugin views |
| Compile-ahead native UI | [Valdi](https://github.com/Snapchat/Valdi) (iOS, Android, macOS), [Lynx](https://github.com/lynx-family/lynx) | No: built for whole apps compiled ahead of time, not third-party plugins loaded at runtime |
| Web view | VS Code, Figma, current Baron design | **Yes, as an escape hatch** for fully custom UI such as ODH's popup |

## Recommendation for Baron

1. **Engine:** JavaScriptCore on macOS, QuickJS-NG on Windows and Linux, as designed. Node or Deno would cost 60–150 MB and give up the per-plugin sandbox, the reason Raycast has none.
2. **Answer Raycast's problem directly:** the host provides a fixed "web platform subset" (`fetch`, `URL`, `TextEncoder`/`TextDecoder`, timers, `AbortController`, `crypto.getRandomValues` and `crypto.subtle.digest`, `structuredClone`, `console`). esbuild bundles pure-JavaScript npm packages; packages that need Node built-ins (`fs`, `child_process`, `net`) are unsupported by design.
3. **Process model:** one sandboxed helper process with one context per plugin, Raycast's first design. A runaway plugin is stopped by killing and restarting the helper; after repeated strikes it is disabled.
4. **Storage:** `storage` (async key-value, JSON values, per plugin, with a quota), `cache` (LRU, may be evicted), `secrets` (Keychain), and read-only `preferences`. All stored by the host, never by plugin code touching the file system.
5. **UI in three tiers:** (a) preferences declared in the manifest, drawn by Baron as a native settings pane; (b) `@baron/ui` React components rendered natively for custom settings and result views; (c) web views for anything else.
6. **Rendering:** SwiftUI on macOS 14+. Raycast chose AppKit in 2020 over SwiftUI stability worries; for forms and lists on macOS 14 SwiftUI is the simpler fit. Send the whole render tree per commit at first; adopt JSON Patch, as Raycast did, only if trees get large.

Open questions for the user are in the design doc's Plugin system section.
