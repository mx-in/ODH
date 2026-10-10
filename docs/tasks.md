# Task backlog: Baron

Tasks extracted from [tec-design.md](tec-design.md), in build order. Each task matches one milestone and ends at that milestone's gate. Features and sub-tasks are split with the single-responsibility rule in [AGENTS.md](../AGENTS.md#task-breakdown-rules).

To start a task, copy it into **Current task** in `AGENTS.md`, then tick items there. Leave this file as the plan. When a task is archived, mark it done here with a link to its archive file.

| Task | Milestone | Status |
| --- | --- | --- |
| task-001-spike | M0 · Spike | Done ([archive](archive/task-001-spike-archive.md)) |
| task-002-selection-bar | M1 · Selection bar | Done ([archive](archive/task-002-selection-bar-archive.md)) |
| task-003-plugin-runtime | M2 · Plugin runtime | Not started |
| task-004-context-and-views | M3 · Context and views | Not started |
| task-005-odh-plugin | M4 · ODH plugin | Not started |
| task-006-release | v1 release | Not started |

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

## task-003-plugin-runtime: run TypeScript and JavaScript actions

**Gate:** sample plugins pass on JavaScriptCore and QuickJS-NG.

- [ ] **Shared contract package** (the cross-platform part)
    - [ ] Write the `SelectionContext` and `TextSpan` types
    - [ ] Write the `Host` interface
    - [ ] Write the manifest JSON Schema
    - [ ] Write `defineActions`
- [ ] **Manifest loading** (Swift)
    - [ ] Parse and validate a manifest against the schema
    - [ ] Evaluate `when` rules: length, regex, content type, apps, editable
    - [ ] Check `apiVersion` (support N and N−1; refuse newer)
- [ ] **Plugin install**
    - [ ] Install from a folder
    - [ ] Install from a URL
    - [ ] Show requested permissions at install
    - [ ] Ask again when an update adds permissions
- [ ] **Helper process**
    - [ ] Create a sandboxed XPC helper with no file or network entitlement
    - [ ] Load one JavaScriptCore context per plugin
    - [ ] Bridge the host's `Promise`s to Swift `async`
    - [ ] Enforce the 10 s limit per action call
    - [ ] Unload a plugin after 60 s idle
    - [ ] Restart the helper after a crash
- [ ] **Host API** (one sub-task per namespace, each checking its permission)
    - [ ] `host.options`
    - [ ] `host.http.fetch` with the host allowlist
    - [ ] `host.clipboard`
    - [ ] `host.selection.replace`
    - [ ] `host.storage`, private per plugin
    - [ ] `host.text.segment` using `NLTokenizer`
    - [ ] `host.ui.toast` and `host.ui.openUrl`
    - [ ] `host.log`, which never records selected text
- [ ] **CLI**
    - [ ] `baron build`: bundle TypeScript with esbuild
    - [ ] `baron dev`: watch, rebuild and reload the plugin
- [ ] **Conformance**
    - [ ] Write a QuickJS-NG test runner that loads a plugin with a mock host
    - [ ] Write two sample plugins (a text transform and a network lookup) with tests
    - [ ] Run the sample plugins' tests on JavaScriptCore and QuickJS-NG in CI

## task-004-context-and-views: give plugins context and rich UI

**Gate:** a plugin reads the sentence in Safari, Chrome, Mail and Notes.

- [ ] **Context builder**
    - [ ] App fields from `NSWorkspace`
    - [ ] Window title and document URL
    - [ ] Page URL and title from `AXWebArea`
    - [ ] AppleScript fallback for the page URL, behind a user setting
    - [ ] Web sentence and paragraph from text markers, joined across the selection
    - [ ] Native-text sentence and paragraph from a ±1,000-character window
    - [ ] PDF sentence and paragraph from Preview's static-text blocks (gap found in task-001's hand checks)
    - [ ] Apply the caps and the `truncated` flag
    - [ ] Convert offsets to UTF-16
    - [ ] Run in the background within the 200 ms budget; actions wait at most 300 ms more
    - [ ] Fill only the fields some enabled plugin has permission for
    - [ ] Wake Chrome or Electron accessibility only for the frontmost app, and only when needed
- [ ] **View runtime**
    - [ ] Show a `WKWebView` panel next to the bar
    - [ ] Serve plugin files through a `plugin://<id>/` URL scheme handler
    - [ ] Apply a Content Security Policy with no direct network or outside navigation
    - [ ] Bridge `host` into the view through a message handler
    - [ ] Implement `host.ui.openView` and `ViewHandle`
- [ ] **Verification**
    - [ ] Write a sample plugin that shows the sentence and paragraph in a view
    - [ ] Check it in Safari, Chrome, Mail and Notes

## task-005-odh-plugin: ODH lookup and Anki from any app

**Gate:** look up a word and add a card from Chrome, Mail and Slack.

- [ ] **Decision needed**
    - [ ] Choose how user-added dictionary scripts get network access (`network:*` or a prompt per host)
- [ ] **Plugin package**
    - [ ] Write the manifest: lookup action, rules, permissions, Anki options
    - [ ] Add a build step that copies `src/dict`, the deinflector and the popup UI from this repo
- [ ] **`api` shim in the view**
    - [ ] `api.fetch` through `host.http.fetch`
    - [ ] `api.deinflect` using the bundled deinflector
    - [ ] `api.locale` and `api.getBuiltin`
- [ ] **Lookup flow**
    - [ ] Load the selected dictionary script in the view
    - [ ] Pass the word, sentence and page URL from the context
    - [ ] Render results with the existing popup UI
- [ ] **Anki**
    - [ ] Send AnkiConnect requests through `host.http.fetch`
    - [ ] Map the word, sentence, URL and definition to note fields
- [ ] **Verification**
    - [ ] Look up a word and add a card from Chrome, Mail and Slack

## task-006-release: ship v1

- [ ] **Packaging**
    - [ ] Sign with Developer ID
    - [ ] Notarize and staple
    - [ ] Build the DMG
- [ ] **Docs**
    - [ ] Write the user guide, covering permissions and excluded apps
    - [ ] Write the plugin author guide
