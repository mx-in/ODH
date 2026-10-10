# Task backlog: Baron

Tasks extracted from [tec-design.md](tec-design.md) and, from task-004 on, from the [plugin platform design](design/plugin-platform/README.md): one task per platform sub-project, in its build order, each ending at the gate written in that sub-project's design. Features and sub-tasks are split with the single-responsibility rule in [AGENTS.md](../AGENTS.md#task-breakdown-rules).

To start a task, copy it into **Current task** in `AGENTS.md`, then tick items there. Leave this file as the plan. When a task is archived, mark it done here with a link to its archive file. Sub-tasks found along the way are added in `AGENTS.md` and end up in the archive.

| Task | Builds | Gate | Status |
| --- | --- | --- | --- |
| task-001-spike | M0 · Spike | Coverage table reviewed; context fields confirmed | Done ([archive](archive/task-001-spike-archive.md)) |
| task-002-selection-bar | M1 · Selection bar | The bar shows in every test app, or the gap is documented | Done ([archive](archive/task-002-selection-bar-archive.md)) |
| task-003-plugin-design | Research and the platform design | The user approves the platform design | In progress |
| task-004-plugin-contract | [01](design/plugin-platform/01-package-and-manifest.md) Package and manifest, `@baron/api` | Schema and Swift validator agree on 30+ manifests | Not started |
| task-005-runtime | [02](design/plugin-platform/02-runtime.md) Runtime stage 1, [03](design/plugin-platform/03-host-api-and-ipc.md) core | A sample plugin runs from the bar; tests pass on both engines | Not started |
| task-006-host-services | [03](design/plugin-platform/03-host-api-and-ipc.md) Host API, [04](design/plugin-platform/04-permissions-and-security.md) Permissions | Every call is permission-checked; prompts are UI-tested | Not started |
| task-007-storage-and-settings | [05](design/plugin-platform/05-storage.md) Storage, [06](design/plugin-platform/06-settings.md) Settings | ODH-shaped settings fill from a mock AnkiConnect | Not started |
| task-008-install | [10](design/plugin-platform/10-install-and-lifecycle.md) Install and lifecycle, [09](design/plugin-platform/09-developer-tooling.md) CLI | Consent works; uninstall leaves nothing behind | Not started |
| task-009-context-builder | [Context capture](tec-design.md#context-capture) | Context arrives only when needed and permitted | Not started |
| task-010-web-views | [07](design/plugin-platform/07-web-views.md) Web views | Panel next to the selection; undeclared hosts blocked | Not started |
| task-011-sandboxed-helper | [02](design/plugin-platform/02-runtime.md#stage-2-the-sandboxed-helper) Runtime stage 2 | The same tests pass; a helper crash recovers | Not started |
| task-012-odh-on-baron | [ODH on Baron](design/plugin-platform/odh-on-baron.md) | The parity checklist passes: the platform is done | Not started |
| task-013-native-views | [08](design/plugin-platform/08-native-views.md) Native views | Form, List and Detail render; same trees on both engines | Not started |
| task-014-release | v1 release | A signed, notarized download | Not started |

---

## task-001-spike: measure what macOS really gives us

**Gate:** coverage table reviewed; context fields confirmed.

- [x] **Decisions needed before code** (open questions from the design)
    - [x] Pick the product name and package scope: baron
    - [x] Confirm the licence: MIT
    - [x] Confirm the minimum macOS version: 14
- [ ] **Project skeleton**
    - [ ] Create the Swift package and app target (menu-bar agent, no Dock icon)
    - [ ] Sign builds with a stable identity (the installed Apple Development one) so the Accessibility grant survives rebuilds
    - [ ] Add the Accessibility permission check and the prompt that opens System Settings
- [ ] **Probe tool** (a throwaway CLI that prints what each API returns for the current selection)
    - [ ] Read `AXSelectedText` from the focused element
    - [ ] Read the web selection via `AXSelectedTextMarkerRange` and `AXStringForTextMarkerRange`
    - [ ] Read the sentence and paragraph via the web text-marker attributes
    - [ ] Read the native-text window via `AXSelectedTextRange` and `AXStringForRange`
    - [ ] Read `AXURL` and the title from the nearest `AXWebArea`
    - [ ] Read the window title and `AXDocument`
    - [ ] Read the selection bounds via `AXBoundsForRange` and `AXBoundsForTextMarkerRange`
    - [ ] Set `AXManualAccessibility` on Electron apps, and read `AXRole` to wake Chrome's tree
    - [ ] Copy through Edit › Copy, with clipboard save and restore
    - [ ] Copy through ⌘C, with clipboard save and restore
- [ ] **Coverage measurement**
    - [ ] Run the probe on the 13 test apps and record each field as works, partial or missing
    - [ ] Measure the time each retrieval step takes per app
    - [ ] Write `docs/research/ax-coverage.md` with the table and its conclusions
- [ ] **Design update**
    - [ ] Update the `SelectionContext` contract in `tec-design.md` to match the measured coverage

## task-002-selection-bar: the bar appears in any app

**Gate:** the bar shows in every test app, or the gap is documented.

- [ ] **Selection monitor**
    - [ ] Detect mouse-up after a drag of 5 px or more
    - [ ] Detect double- and triple-click
    - [ ] Detect ⇧-click
    - [ ] Detect ⇧-arrow and ⌘A, debounced 300 ms
    - [ ] Record a window drag (window moved or resized between mouse-down and mouse-up)
- [ ] **Hotkey**
    - [ ] Add KeyboardShortcuts and record one configurable shortcut
    - [ ] Send the hotkey trigger straight to retrieval, skipping the gate
- [ ] **Gate**
    - [ ] Reject apps on the exclusion list, with the default list
    - [ ] Reject secure text fields and secure keyboard input
    - [ ] Reject roles that cannot hold text
    - [ ] Reject window drags
- [ ] **Text retriever**
    - [ ] Define the `TextRetriever` protocol
    - [ ] Wrap SelectedTextKit behind it
    - [ ] Apply a 0.5 s timeout to every AX call
    - [ ] Retry the web step up to 6 times within 300 ms
    - [ ] ~~Mark our clipboard writes with `org.nspasteboard.TransientType`~~ dropped: the copy is written by the source app, so Baron can't mark it (see `docs/research/ax-coverage.md`)
    - [ ] Choose the chain's starting step from per-app rules
- [ ] **Action bar window**
    - [ ] Show a non-activating `NSPanel` that never takes focus
    - [ ] Position it above the selection, or below near the top of the screen; fall back to the mouse position
    - [ ] Close it on an outside click, key press, scroll or app switch
    - [ ] Render action buttons from a list of actions
- [ ] **Selection pipeline** (added during task-002)
    - [ ] Run trigger → gate → retrieval → bar, skipping the gate for the hotkey
    - [ ] Offer the built-in actions for the text and perform the chosen one
    - [ ] Drop a run that a newer trigger has replaced
- [ ] **Built-in actions**
    - [ ] Copy
    - [ ] Search with a configurable URL template
    - [ ] Open a link found in the selection
- [ ] **Settings**
    - [ ] Pause and resume the bar from the menu-bar item
    - [ ] Edit the excluded apps
    - [ ] Launch at login
- [ ] **Logging**
    - [ ] Log text length and the retrieval step used, never the text
- [ ] **Verification**
    - [ ] Run the bar on the 13 test apps and record the results in `docs/research/ax-coverage.md`

## task-003-plugin-design: research and design the plugin platform

**Gate:** the user approves the [plugin platform design](design/plugin-platform/README.md).

- [ ] **Research** ([plugin-runtime.md](research/plugin-runtime.md))
    - [ ] How Raycast runs extensions: runtime, process model, React-to-native UI, preferences, storage
    - [ ] Other plugin systems: PopClip, VS Code, Obsidian, Figma, Zed, Alfred
    - [ ] JavaScript engines: JavaScriptCore, QuickJS-NG, Hermes, Node, Bun, Deno, WebAssembly
    - [ ] Native UI from JavaScript: React reconcilers, declarative schemas, web views
    - [ ] Storage and secrets
- [ ] **Design**
    - [ ] Update the app design's Plugin system section
    - [ ] Design each platform sub-project in its own file
    - [ ] Map ODH onto the platform as the success test
    - [ ] Re-plan this backlog from the design
- [ ] **Review**
    - [ ] The user reads the design and approves it, or asks for changes

## task-004-plugin-contract: the manifest and types everything else builds on

**Design:** [01 Package and manifest](design/plugin-platform/01-package-and-manifest.md), the types in [03](design/plugin-platform/03-host-api-and-ipc.md), packages in [09](design/plugin-platform/09-developer-tooling.md#packages).
**Gate:** the JSON Schema and the Swift validator agree on at least 30 valid and invalid manifests; `when` rules and localisation are unit tested; ODH's manifest validates.

- [ ] **Bun workspace**
    - [ ] Create the `packages/` workspace with an empty `@baron/api` and a `bun test` script
    - [ ] Add the workspace's tests to the checks in `AGENTS.md`
- [ ] **`@baron/api` types**
    - [ ] Write the manifest types, including every preference type
    - [ ] Write `SelectionContext`, `TextSpan` and `ActionResult`
    - [ ] Write `Host` and `ViewHandle` for apiVersion 1
    - [ ] Write `BaronError` and the error codes
    - [ ] Write `definePlugin`
- [ ] **Manifest JSON Schema**
    - [ ] Write the schema (draft 2020-12) for the package fields and actions
    - [ ] Add the preference types to the schema
    - [ ] Test that the schema and the TypeScript types describe the same fields
- [ ] **Manifest corpus**
    - [ ] Write at least 30 valid and invalid manifests, each with its expected errors as JSON Pointers
    - [ ] Run the corpus against the JSON Schema
- [ ] **Swift manifest model** (BaronCore)
    - [ ] Decode a manifest into Swift types
    - [ ] Check that action and preference IDs are unique and permission names are known
    - [ ] Check that paths stay inside the package and icons are SVG
    - [ ] Compile each `regex` as JavaScript and as ICU
    - [ ] Check `apiVersion`, `minBaronVersion` and `platforms`
    - [ ] Report each error with a JSON Pointer
    - [ ] Run the shared corpus in Swift tests
- [ ] **`when` rules** (BaronCore)
    - [ ] Evaluate `minLength` and `maxLength` in UTF-16 units
    - [ ] Evaluate `regex`
    - [ ] Classify the text as `word`, `url`, `email`, `number` or `text`
    - [ ] Evaluate `apps`, `excludeApps` and `editable`
- [ ] **Localisation** (BaronCore)
    - [ ] Resolve `%key%` strings through the preferred languages, then `defaultLocale`, then the key itself
- [ ] **ODH manifest**
    - [ ] Write `plugins/odh/manifest.json`: the Look up action, permissions and every preference from the [options mapping](design/plugin-platform/odh-on-baron.md#odhs-options-as-preferences)
    - [ ] Convert ODH's `_locales` (`en`, `zh_CN`, `zh_TW`) into `locales/en.json`, `zh-Hans.json` and `zh-Hant.json`
- [ ] **Verification**
    - [ ] Check the gate: both checkers agree on the corpus, and ODH's manifest validates in both

## task-005-runtime: run plugin code from the bar, in-process

**Design:** [02 Runtime](design/plugin-platform/02-runtime.md) stage 1, the envelopes and router in [03](design/plugin-platform/03-host-api-and-ipc.md), the build and test commands in [09](design/plugin-platform/09-developer-tooling.md).
**Gate:** a sample plugin with an uppercase action and a `fetch`-based lookup runs from Baron's bar; its tests pass on JavaScriptCore and QuickJS-NG with the same prelude; timers, errors, time limits, idle unload and reload are tested.

- [ ] **Prelude** (`@baron/runtime`)
    - [ ] Build call envelopes and match results to calls by `id`
    - [ ] Build the `host` object over `__baronNative`
    - [ ] Serve dispatches: find the export, call it, await it, reply with a result or a classified error
    - [ ] Provide `console`, the timer functions and `queueMicrotask`
    - [ ] Polyfill `URL` and `URLSearchParams`
    - [ ] Polyfill `TextEncoder`, `TextDecoder`, `atob`, `btoa` and `structuredClone`
    - [ ] Polyfill `AbortController` and `AbortSignal`
    - [ ] Provide `fetch`, `Request`, `Response` and `Headers` over `host.http`
    - [ ] Compile the prelude to one script and copy it into Baron.app
- [ ] **Engine contexts** (Swift)
    - [ ] Create one `JSVirtualMachine` and context per plugin, on its own serial queue
    - [ ] Expose `__baronNative.send` with a completion
    - [ ] Back the timer functions with native timers on the plugin's queue
    - [ ] Provide `crypto.getRandomValues`, `crypto.randomUUID` and `crypto.subtle.digest`
    - [ ] Load the prelude and the bundle within 2 s, and mark a plugin that fails to load as broken
    - [ ] Enforce each dispatch's time limit and abort its signal
    - [ ] Disable a plugin stuck in a synchronous loop for 10 s, and one with 3 strikes in 10 minutes
    - [ ] Unload a context after 60 s idle and load it again on the next need
- [ ] **Host router** (Swift)
    - [ ] Decode envelopes and route `ns.method` to a service
    - [ ] Return the error codes from the design
    - [ ] Serve `environment`, `preferences` (manifest defaults until task-007), `log` and `ui.toast`
    - [ ] Serve `http.fetch` with its time and size limits (permission checks come in task-006)
- [ ] **Bar integration**
    - [ ] Load plugins from a development folder (installing comes in task-008)
    - [ ] Show plugin actions whose `when` rules match, after the built-in ones
    - [ ] Dispatch a click with `text`, `source`, `editable`, `app` and `platform` (other context fields come in task-009)
    - [ ] Carry out action results: copy, replace, toast, open URL
    - [ ] Show a plugin's error as a toast naming the plugin
- [ ] **Tooling**
    - [ ] `baron build`: bundle `src/` into one classic script with an inline source map
    - [ ] `baron build` checks: manifest, Node built-ins, bundle size, `eval` without `code.dynamic`
    - [ ] `@baron/test`: a mock host with in-memory services
    - [ ] Run plugin tests on JavaScriptCore through `node:vm`
    - [ ] Run plugin tests on QuickJS-NG through `qjs`, with envelopes on standard input and output
    - [ ] `baron test --engine jsc|quickjs|all`
- [ ] **Examples**
    - [ ] Write the uppercase action example with tests
    - [ ] Write the `fetch`-based lookup example with tests
- [ ] **Verification**
    - [ ] Test timers, errors, time limits, idle unload and reload
    - [ ] Measure load time, dispatch overhead and idle memory against the targets in the design
    - [ ] Run both examples from the bar in a UI test

## task-006-host-services: every host call, checked

**Design:** [03 Host API and IPC](design/plugin-platform/03-host-api-and-ipc.md), [04 Permissions and security](design/plugin-platform/04-permissions-and-security.md).
**Gate:** every host method rejects calls without its permission, and those needing a user action reject without one; the network matcher passes its corpus; run-time prompts work end to end in a UI test; contract tests pass on both engines.

- [ ] **Permission gate**
    - [ ] Hold each plugin's granted set: install permissions plus saved run-time grants
    - [ ] Check every routed call before its service runs
- [ ] **Network matcher**
    - [ ] Match hosts, subdomain wildcards, ports and schemes
    - [ ] Match private, link-local and loopback addresses only by an exact entry
    - [ ] Resolve hosts before connecting, so a public name can't reach a private address
    - [ ] Check every redirect hop
    - [ ] Pass the matcher test corpus
- [ ] **User-action tracker**
    - [ ] Record bar clicks and panel input per plugin
    - [ ] Reject side-effecting calls without a user action in the last 5 s
- [ ] **Services**
    - [ ] `http.fetch`: methods, headers, bodies, an ephemeral session per plugin, 5 redirects
    - [ ] `clipboard.readText` and `clipboard.writeText`
    - [ ] `selection.replace`: set `AXSelectedText`, else paste with the clipboard saved and restored
    - [ ] `text.segment` with `NLTokenizer`
    - [ ] `ui.openUrl` for `https`, `http` and `mailto`, and `ui.openSettings`
    - [ ] `permissions.query` and `permissions.request`
- [ ] **Run-time prompt** (UI)
    - [ ] Show the native prompt naming the plugin and host: Deny, Allow Once, Always Allow; one at a time
    - [ ] Save Always Allow, and remember Deny for 24 hours
- [ ] **Install sheet** (UI, used by task-008)
    - [ ] List permissions in plain words, grouped as Reads, Connects to, Can and Stores, with the disclosures
- [ ] **Logging**
    - [ ] Send plugin log lines to the system log marked private
- [ ] **Contract tests**
    - [ ] Call every method from JavaScript on both engines and check results and error codes
- [ ] **Verification**
    - [ ] UI test of the prompt: Deny, Allow Once, Always Allow (revoking is tested in task-007)

## task-007-storage-and-settings: plugins keep data, users set options

**Design:** [05 Storage](design/plugin-platform/05-storage.md), [06 Settings](design/plugin-platform/06-settings.md).
**Gate:** each store passes its unit tests; a test plugin shaped like ODH renders every preference type and fills its dropdowns from a mock AnkiConnect; list, checklist, button, secret and revoke work in a UI test.

- [ ] **Data folders**
    - [ ] Create each plugin's data and cache folders
- [ ] **Preferences store**
    - [ ] Save and load `preferences.json`, with defaults from the manifest
- [ ] **Storage**
    - [ ] Store JSON values in SQLite, one actor per plugin
    - [ ] Enforce the 5 MB quota and 1 MB per value
    - [ ] Serve `host.storage`
- [ ] **Cache**
    - [ ] Store strings in SQLite in the Caches folder, evicting the least recently read past 10 MB
    - [ ] Serve `host.cache`
- [ ] **Secrets**
    - [ ] Keep secrets in the Keychain per plugin, not synchronisable
    - [ ] Serve `host.secrets` behind the `secrets` permission
- [ ] **Data management**
    - [ ] Report usage; Clear cache; Reset plugin data
    - [ ] Remove every store and grant of a plugin (used by uninstall)
- [ ] **Settings: Plugins section** (UI)
    - [ ] List installed plugins with Enabled switches
    - [ ] Show a plugin's page: header, preferences, permissions, data, about
- [ ] **Settings: preference controls** (UI)
    - [ ] `text`, `number` and `checkbox`
    - [ ] `dropdown` and `checklist` with static options
    - [ ] `list` with add, remove and reorder
    - [ ] `secret`
    - [ ] `file`, `directory` and `app`
    - [ ] `button` with its result line, and `heading`
- [ ] **Settings: options from the plugin**
    - [ ] Call options providers with a spinner; show errors with Retry
    - [ ] Keep a saved value missing from new options, marked "not found"
    - [ ] Reload a field's options when a field in its `dependsOn` changes
- [ ] **Settings: saving**
    - [ ] Validate and save 0.5 s after the last edit; show inline errors
    - [ ] Refresh `host.preferences` before each dispatch, and reload a loaded plugin when they change
    - [ ] Open the settings page with empty required fields highlighted when an action needs them
- [ ] **Settings: Permissions section**
    - [ ] List run-time grants with Remove buttons
- [ ] **Verification**
    - [ ] Unit test each store: persistence across reload, quotas, per-value limits, eviction order; 1,000 writes and reads in under a second
    - [ ] UI test with the ODH-shaped plugin and a mock AnkiConnect, including revoking a grant

## task-008-install: install, update and remove plugins

**Design:** [10 Install and lifecycle](design/plugin-platform/10-install-and-lifecycle.md), install consent in [04](design/plugin-platform/04-permissions-and-security.md#install-and-update-consent), the CLI and development mode in [09](design/plugin-platform/09-developer-tooling.md).
**Gate:** install from a folder and a `.baronplugin` file, including refused cases; an update that adds a permission waits for consent; disable, enable and uninstall work, leaving nothing on disk or in the Keychain; a bundled sample is offered at first launch; bar settings pass a UI test; a first-time author gets from `baron create` to their action on the bar in under 2 minutes.

- [ ] **Package reading**
    - [ ] Read a plugin folder
    - [ ] Unzip a `.baronplugin`: files only, no symlinks, at most 50 MB
- [ ] **Install**
    - [ ] Refuse an invalid manifest, an unsupported `apiVersion`, a newer `minBaronVersion` or an excluded platform, with the reason
    - [ ] Show the install sheet, warning when the same `id` comes from another source
    - [ ] Copy the package to `Plugins/<id>/<version>/`
    - [ ] Run `onInstall` with a 10 s limit and show a failure
- [ ] **States**
    - [ ] Track Enabled, Disabled, Needs consent, Broken and Suspended
    - [ ] Disable, enable, and re-enable a suspended plugin
- [ ] **Updates**
    - [ ] Treat a higher version as an update; ask before installing a lower or equal one
    - [ ] Install silently with the same or fewer permissions; with new ones, wait in Needs consent while the old version keeps working
    - [ ] Run `onUpdate` before the first dispatch, and delete the previous version after the first successful load
- [ ] **Uninstall**
    - [ ] Confirm, then remove the package and all of its data
- [ ] **Sources**
    - [ ] Add from Folder… in Settings
    - [ ] Open `.baronplugin` files
    - [ ] Handle `baron://install?url=https://…`
    - [ ] Offer bundled plugins at first launch
- [ ] **Bar settings** (UI)
    - [ ] Reorder actions by drag, with new ones at the end
    - [ ] Show or hide each action
    - [ ] Run on selection for `autoRun: "allowed"` actions, optionally limited to some apps
    - [ ] Give an action its own hotkey
- [ ] **Development mode**
    - [ ] Turn it on in Settings › Advanced and listen on a same-user socket
    - [ ] Load a registered folder as "Development" and reload it on each rebuild
    - [ ] Stream logs and errors with TypeScript line numbers; make contexts inspectable
- [ ] **CLI**
    - [ ] `baron create` with the `action`, `lookup` and `settings` templates
    - [ ] `baron dev`
    - [ ] `baron validate`, and `baron pack` printing the SHA-256
- [ ] **Verification**
    - [ ] Check the gate, including disk and Keychain after uninstall
    - [ ] Time a first-time author from `baron create` to the action on the bar

## task-009-context-builder: give actions the context they may read

**Design:** [Context capture](tec-design.md#context-capture) in the app design, context permissions in [04](design/plugin-platform/04-permissions-and-security.md#permission-catalogue), `needs` in [01](design/plugin-platform/01-package-and-manifest.md#actions). The readers from tasks 001 and 002 already exist; this task turns them into each action's `SelectionContext`.
**Gate:** a test plugin receives sentence, paragraph, page and window in Safari, Chrome, Mail, Notes, Pages and TextEdit, and receives none of them without the permission.

- [ ] **Assembly**
    - [ ] Build a `SelectionContext` from the existing readers
    - [ ] Read only the fields that some matching action `needs` and its plugin is granted
    - [ ] Give each action only its own `needs` and granted fields
- [ ] **Timing**
    - [ ] Read context in the background right after the text, within 200 ms; an action waits at most 300 ms more
    - [ ] Wake Chrome and Electron accessibility only for the frontmost app, and only when a field needs it
- [ ] **Fields**
    - [ ] Apply the caps and the `truncated` flag on the web paths, as the native path already does
    - [ ] Check that every offset is in UTF-16 units
    - [ ] Fall back to AppleScript for the page URL, behind a user setting
    - [ ] Read the sentence and paragraph from Preview's PDF text blocks (gap from task-001)
- [ ] **Verification**
    - [ ] Run the test plugin in the six apps in `baron-uitest`, with and without the permissions

## task-010-web-views: plugin pages in a result panel

**Design:** [07 Web views](design/plugin-platform/07-web-views.md).
**Gate:** a sample plugin opens a result panel next to the selection, sized to its content; images and audio load from declared hosts and nothing loads from undeclared ones; `baron.*` calls from the page obey the plugin's permissions; messages flow both ways; the panel closes and pins as designed and follows dark mode.

- [ ] **Result panel** (UI)
    - [ ] Show a panel next to the selection that never takes focus from the source app, with Baron's header: icon, name, pin, close
    - [ ] Close it on an outside click, Escape, an app switch or a new selection unless pinned; one panel at a time
    - [ ] Size it to its content, up to 640 points
- [ ] **Serving pages**
    - [ ] Serve `baron-plugin://<id>/` from the installed package
    - [ ] Give each plugin a non-persistent data store
    - [ ] Block navigation to other origins and `window.open`; open links in the browser
    - [ ] Apply the Content Security Policy, with declared hosts for images and media, and `'unsafe-eval'` only with `code.dynamic`
- [ ] **Page bridge**
    - [ ] Inject `window.baron` with the host API, taking the plugin's identity from the page's origin
    - [ ] `baron.view`: data, messages, resize and close
    - [ ] `host.ui.openWebView` and `ViewHandle` on the engine side
- [ ] **Look and feel**
    - [ ] Colour variables, dark mode and locale
    - [ ] Play audio without an extra click
- [ ] **Lifecycle**
    - [ ] Keep a closed web view loaded for 30 s
- [ ] **Settings page**
    - [ ] Show a plugin's `settingsPage` under its generated preferences
- [ ] **Tooling**
    - [ ] Add the `webview` template and example
- [ ] **Verification**
    - [ ] Check the gate in a UI test; measure first paint (under 150 ms warm, 400 ms cold)

## task-011-sandboxed-helper: move plugins out of Baron's process

**Design:** [02 Runtime, stage 2](design/plugin-platform/02-runtime.md#stage-2-the-sandboxed-helper).
**Gate:** the runtime, host API and UI tests pass with plugins in the helper; killing the helper mid-action gives `unavailable` and the next action works.

- [ ] **Helper**
    - [ ] Create `BaronPluginHost.xpc` with App Sandbox and no file or network entitlements
    - [ ] Move engine contexts into the helper, sending it the prelude and bundles over the connection
    - [ ] Carry the envelopes over `NSXPCConnection`
- [ ] **Recovery**
    - [ ] Fail pending calls with `unavailable`, relaunch the helper on the next need, and count a strike
    - [ ] Restart the helper on a stuck loop or above 512 MB
- [ ] **Verification**
    - [ ] Run the runtime, host API and UI tests against the helper
    - [ ] Kill the helper mid-action and check recovery

## task-012-odh-on-baron: ODH as a Baron plugin (the success test)

**Design:** [ODH on Baron](design/plugin-platform/odh-on-baron.md).
**Gate:** every item of the [parity checklist](design/plugin-platform/odh-on-baron.md#parity-checklist-gate-for-task-012) passes. The platform is done.

- [ ] **Package and build**
    - [ ] Build `plugins/odh/` by copying the dictionary scripts, popup UI and deinflector from `src/`
    - [ ] Keep the Chrome extension building from the same sources
- [ ] **Engine side**
    - [ ] Look up: take the word, the context sentences and the URL, and open the popup
    - [ ] Options providers: dictionaries, decks, note types and note fields from AnkiConnect
    - [ ] The Test connection button
    - [ ] `onInstall`
- [ ] **Page side**
    - [ ] The `api` shim onto `window.baron`: fetch, deinflect, locale, built-in data
    - [ ] Load the chosen built-in dictionary script and render with the popup UI
    - [ ] Load user scripts from URLs: host prompt, cache, run in the page
    - [ ] Play pronunciation audio with `<audio>`
    - [ ] Add a card through AnkiConnect with the field mapping, tags and duplicate setting
- [ ] **Bundling**
    - [ ] Ship ODH inside Baron.app and offer it at first launch
- [ ] **Tests**
    - [ ] Engine-side tests on both engines
    - [ ] UI tests for lookup and adding a card in `baron-uitest`
- [ ] **Verification**
    - [ ] Run the parity checklist, comparing 20 test words with the Chrome extension

## task-013-native-views: React components drawn with SwiftUI

**Design:** [08 Native views](design/plugin-platform/08-native-views.md).
**Gate:** a sample plugin shows a Form with every field type, a searchable List with actions and a Detail with Markdown; navigation works; an event round trip takes under 50 ms; render trees are identical on both engines.

- [ ] **`@baron/ui`**
    - [ ] Write the components: Form and its fields, List, Detail, ActionPanel, Action
    - [ ] Write the reconciler that keeps a plain-object tree
    - [ ] Send trees with handler IDs, at most once per 16 ms
- [ ] **SwiftUI renderer**
    - [ ] Map each node type to a view, with a placeholder for unknown types
    - [ ] Keep text fields uncontrolled
    - [ ] Send events back; push and pop navigation
    - [ ] Show views in the result panel and as a `settingsView`
- [ ] **Verification**
    - [ ] Check the gate, with snapshot tests of the trees on both engines

## task-014-release: ship v1

**Gate:** a Developer ID–signed, notarized download.

- [ ] **Packaging**
    - [ ] Sign the app and the helper with Developer ID
    - [ ] Notarize and staple
    - [ ] Build the DMG
- [ ] **Packages**
    - [ ] Publish `@baron/api`, `@baron/test` and `@baron/cli` to npm
- [ ] **Docs**
    - [ ] Write the user guide, covering permissions, plugins and excluded apps
    - [ ] Write the plugin author guide from the templates
