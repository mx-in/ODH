# task-002-selection-bar archive

**Finished:** 2026-10-10 · **Gate:** the bar shows in every measured app; gaps documented; approved by the user

**Summary:** Baron detects selections (drag, multi-click, ⇧-click, keyboard, hotkey), vetoes unsafe ones with the gate, reads text through a four-step chain, and shows a non-activating bar with Copy, Search and Open Link. Settings cover pause, excluded apps, search URL, hotkey and launch at login; logs never hold selected text. Added on request: a debug panel and an Xcode project. Time to bar is 41–110 ms after an app's first selection (105–204 ms for the first).

**Task:** task-002-selection-bar: the bar appears in any app (gate: the bar shows in every test app, or the gap is documented)
**Started:** 2026-10-10 · **Agent:** Claude (Claude Code) · runs while task-001 waits for the user

- [x] Selection monitor (commit 6d435a7)
    - [x] Detect mouse-up after a drag of 5 px or more
    - [x] Detect double- and triple-click
    - [x] Detect ⇧-click
    - [x] Detect ⇧-arrow and ⌘A, debounced 300 ms
    - [x] Record a window drag (window moved or resized between mouse-down and mouse-up)
- [x] Hotkey (commit de69a91; no default shortcut, recorded in Settings)
    - [x] Add KeyboardShortcuts and record one configurable shortcut
    - [x] Send the hotkey trigger straight to retrieval, skipping the gate
- [x] Gate (commit 748eca3)
    - [x] Reject apps on the exclusion list, with the default list
    - [x] Reject secure text fields and secure keyboard input
    - [x] Reject roles that cannot hold text
    - [x] Reject window drags
- [x] Text retriever (commit 45f85d1)
    - [x] Define the `TextRetriever` protocol
    - [x] Wrap SelectedTextKit behind it
    - [x] Apply a 0.5 s timeout to every AX call (global default set on the system-wide element, which covers SelectedTextKit too)
    - [x] Retry the web step up to 6 times within 300 ms
    - [x] Choose the chain's starting step from per-app rules
- [x] Action bar window (commit eaab00e)
    - [x] Show a non-activating `NSPanel` that never takes focus
    - [x] Position it above the selection, or below near the top of the screen; fall back to the mouse position
    - [x] Close it on an outside click, key press, scroll or app switch
    - [x] Render action buttons from a list of actions
- [x] Built-in actions (commit 9e3b97d)
    - [x] Copy
    - [x] Search with a configurable URL template
    - [x] Open a link found in the selection
- [x] Selection pipeline (commit feba391; found missing while building; wires the parts together)
    - [x] Run trigger → gate → retrieval → bar, skipping the gate for the hotkey
    - [x] Offer the built-in actions for the text and perform the chosen one
    - [x] Drop a run that a newer trigger has replaced
- [x] Settings (commit 5bb6df5; window also holds the hotkey recorder and search URL)
    - [x] Pause and resume the bar from the menu-bar item
    - [x] Edit the excluded apps
    - [x] Launch at login
- [x] Logging (commit: see next; `log stream --predicate 'subsystem == "org.odh.baron"'`)
    - [x] Log text length and the retrieval step used, never the text
- [x] Verification (automated by `baron-uitest`, which also checks the bar)
    - [x] Run the bar on the test apps: it appeared and its Copy button worked in all 8 measured apps
- [x] Debug panel (commit: see next; user request 2026-10-10; menu "Show Debug Panel" or `open build/Baron.app --args --debug-panel`)
    - [x] Build a debug snapshot from a pipeline outcome and a probe report (`BaronCore`, unit tested)
    - [x] Show it in a floating, non-activating panel toggled from the menu-bar icon (checked in TextEdit by reading the panel through Accessibility)
- [x] Sentence and paragraph UI-test cases (user request 2026-10-10)
    - [x] Grade word, sentence and paragraph selections against their own expected text (commit edcb838)
    - [x] Add drag and triple-click input, and word rectangles for drag end points (commit e481c50)
    - [x] Run all three modes per app in `baron-uitest` and `uitest-all.sh` (commit e481c50)
    - [x] Fix what they found: paragraph spill in native, Chromium and WebKit (5b91f5b, engine choice), Pages tree and focused-window search (d082f47)
    - [x] Re-run the apps and update `docs/research/ax-coverage.md` (8 apps pass all modes)
- [x] Bar in the hand-checked apps: Pages, Preview, VS Code ✓ by hand; Slack skipped
- [x] Xcode project (user request 2026-10-10; commit: see next): `macos/Xcode/Baron.xcodeproj`, generated from `project.yml` by XcodeGen, signed with team R24YD8KS22
- [x] Gate: the user reviewed and approved tasks 1–2 (2026-10-10)

**Notes for the next agent:** all task-002 code is committed and unit tested (76 tests in `BaronCore`). The user tried the bar by hand on 2026-10-10, and `baron-uitest` verified it in 8 apps. **Stop here:** the user reviews tasks 1–2 and adds UI automation tests before task-003 starts. To try the bar: `cd macos && scripts/build-app.sh && open build/Baron.app`, grant Accessibility to Baron, then select text in another app. Known gaps: Pages, Preview, VS Code and Slack are unmeasured; a copy-fallback copy can still be recorded by clipboard managers; the settings window needs the built `.app` for launch at login. UI elements carry accessibility identifiers for automation: `baron.actionBar`, `baron.action.<id>`, `baron.settings`, `settings.pause`, `settings.searchTemplate`, `settings.excludedApps`, `settings.launchAtLogin`.

**Notes for the next agent:** the probe was checked by an agent on TextEdit only (native text: every field works). Web fields and copy steps still need a person in Safari/Chrome. Run `macos/.build/debug/baron-probe --delay 3` (or `--app <bundle-id>`, `--copy`, `--json`). The user approved working on task-002 while task-001's coverage measurement waits for them. Stop before task-003; the user reviews tasks 1–2 and adds UI automation tests first.
