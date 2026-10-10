# Agent guide

## Current task

**Task:** task-001-spike: measure what macOS really gives us (gate: coverage table reviewed; context fields confirmed)
**Started:** 2026-10-10 · **Agent:** Claude (Claude Code)

- [x] Decisions needed before code (commit 37e5f1e)
    - [x] Product name: **baron** (package scope `@baron`, CLI `baron`)
    - [x] Licence: MIT
    - [x] Minimum macOS: 14
    - [x] Code location: `macos/` in this repo
    - [x] Record the decisions in `docs/tec-design.md`
- [x] Project skeleton (commit 8056622)
    - [x] Create the Swift package and app target (menu-bar agent, no Dock icon)
    - [x] Sign builds with the installed Apple Development identity so the Accessibility grant survives rebuilds
    - [x] Add the Accessibility permission check and the prompt that opens System Settings
- [x] Probe tool (commit 52526d9; `macos/Sources/baron-probe`, readers in `BaronPlatform/Readers`)
    - [x] Read `AXSelectedText` from the focused element
    - [x] Read the web selection via `AXSelectedTextMarkerRange` and `AXStringForTextMarkerRange`
    - [x] Read the sentence and paragraph via the web text-marker attributes
    - [x] Read the native-text window via `AXSelectedTextRange` and `AXStringForRange`
    - [x] Read `AXURL` and the title from the nearest `AXWebArea`
    - [x] Read the window title and `AXDocument`
    - [x] Read the selection bounds
    - [x] Wake Electron (`AXManualAccessibility`) and Chrome (`AXRole`) accessibility
    - [x] Copy through Edit › Copy, with clipboard save and restore
    - [x] Copy through ⌘C, with clipboard save and restore
- [ ] Coverage measurement (automated with `baron-uitest`; commits 4a5a8b4, 8824d00, 6579c24, 2588186, edcb838, e481c50)
    - [x] Move the probe's reading logic into `BaronPlatform` so the CLI and UI tests share it
    - [x] Grade a probe report against the fixture's expected text (`BaronCore`, unit tested)
    - [x] Add input automation and `baron-uitest` with word, sentence and paragraph modes
    - [x] Run the test apps: 8 apps pass every field in all three modes; Pages passes for words
    - [x] Fix what the runs found (bc89053, b54ac9f, 5b91f5b, e79493c, d082f47)
    - [x] Write the table and conclusions in `docs/research/ax-coverage.md`
    - [x] Hand checks by the user: Pages ✓; VS Code text ✓ via copy, no context (expected); Preview text ✓, no context (gap); Slack not checked
    - [x] Fix the crash the hand checks found in Alacritty, PDF Expert and Preview (retry() under the web step)
    - [ ] **▶ IN PROGRESS** User re-checks Alacritty, PDF Expert and Preview with the fixed build
    - [ ] Read sentence and paragraph from Preview's PDF text blocks (gap found by hand; may move to task-004)
    - [x] Measure time from trigger to bar per app: warm 41–110 ms, first selection in an app 105–204 ms (commits: perf + test, see log)
    - [x] Grade the app Baron detects itself, not the one the test names: matched in all 23 selections
    - [ ] Check the copy fallback with a clipboard manager running
- [x] Design update
    - [x] Correct the design's claim that Baron marks the copy as transient (95c454b)
    - [x] Update "Context capture" with the per-engine methods: Chromium tree, WebKit markers, iWork wake-up, VS Code without editor text (commit: see next)
    - [x] Add the `AXEnhancedUserInterface` side effect to the risks
    - [x] Write the `SelectionContext` decision into the design: which fields v1 promises, which stay optional
- [ ] Gate: the user reviews the coverage table (then archive this task)

**Notes for the next agent:** coverage is measured by `macos/scripts/uitest-all.sh` (drives the mouse; see `docs/research/ax-coverage.md`). Hand checks use the debug panel: `open macos/build/Baron.app --args --debug-panel`. The user approved working on task-002 while task-001 waits for them.

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
- [ ] Bar in the hand-checked apps (Pages, Preview, VS Code, Slack): covered by task-001's hand checks
- [x] Xcode project (user request 2026-10-10; commit: see next): `macos/Xcode/Baron.xcodeproj`, generated from `project.yml` by XcodeGen, signed with team R24YD8KS22
- [ ] Gate: the user reviews tasks 1–2 (then archive this task)

**Notes for the next agent:** all task-002 code is committed and unit tested (76 tests in `BaronCore`). The user tried the bar by hand on 2026-10-10, and `baron-uitest` verified it in 8 apps. **Stop here:** the user reviews tasks 1–2 and adds UI automation tests before task-003 starts. To try the bar: `cd macos && scripts/build-app.sh && open build/Baron.app`, grant Accessibility to Baron, then select text in another app. Known gaps: Pages, Preview, VS Code and Slack are unmeasured; a copy-fallback copy can still be recorded by clipboard managers; the settings window needs the built `.app` for launch at login. UI elements carry accessibility identifiers for automation: `baron.actionBar`, `baron.action.<id>`, `baron.settings`, `settings.pause`, `settings.searchTemplate`, `settings.excludedApps`, `settings.launchAtLogin`.

**Notes for the next agent:** the probe was checked by an agent on TextEdit only (native text: every field works). Web fields and copy steps still need a person in Safari/Chrome. Run `macos/.build/debug/baron-probe --delay 3` (or `--app <bundle-id>`, `--copy`, `--json`). The user approved working on task-002 while task-001's coverage measurement waits for them. Stop before task-003; the user reviews tasks 1–2 and adds UI automation tests first.

<!--
Template while a task is active (replace the line above):

**Task:** task-NNN-short-name: one-line goal
**Started:** YYYY-MM-DD · **Agent:** who is working on it

- [x] Feature 1: done (commit abc1234)
- [ ] **▶ IN PROGRESS** Feature 2: what is being built
    - [x] Sub-task 2.1
    - [ ] Sub-task 2.2 (next step: …)
- [ ] Feature 3: not started

**Notes for the next agent:** state that isn't in the code yet (half-made decisions, blockers, files touched but not committed).
-->

ODH is a Chrome (Manifest V3) extension for looking up words and adding them to Anki. Its source is in `src/`, and its tests are in `tests/`.

## Design docs

- [Selection Popup App — Technical Design](docs/tec-design.md): the planned macOS selection bar (Swift host, TypeScript/JavaScript plugins), with ODH as its first plugin. Read it before working on that app or on code shared with it.
- [Task backlog](docs/tasks.md): the design split into tasks, features and sub-tasks. Start the next task from here.
- Extension background and development notes: [doc/](doc/).

## Checks

Run these before every commit:

```sh
npm run lint
npm run test:contracts
npm run test:unit
```

When `macos/` changed, also run:

```sh
cd macos && swift build && swift test
```

Anything that needs the Accessibility grant or real selections (the probe, the bar in other apps) can't be checked by an agent. List it under **Notes for the next agent** for the user to verify.

## Task breakdown rules

Split work by the single-responsibility principle: every item has exactly one reason to change.

- **Task = one goal** with one acceptance gate (for the selection app, one milestone). Planned tasks live in [docs/tasks.md](docs/tasks.md).
- **Feature = one component or concern**, such as the gate, the text retriever or the host's `http` namespace. If its name needs "and" to describe two separate things, split it.
- **Sub-task = one behaviour you can verify on its own**, finished in one sitting and small enough for one commit. Write it as a verb plus an object ("Reject secure text fields"), not as an area ("security").
- **Keep layers apart:** contract, platform code and UI are separate sub-tasks, even inside one feature, so each changes for one reason only.
- **Open decisions are their own items**, placed before the code that depends on them.
- **Verification is its own item**, at the end of the feature or task it checks.
- If a sub-task turns out to need two commits, split it in the checklist before continuing.

## Task tracking rules

Every task keeps its checklist in **Current task** at the top of this file, so another agent can take over after an interruption.

1. **Start:** before writing code, replace `_No active task._` with the task name, the start date, and a checklist that splits the task into features, with sub-tasks under each. Number tasks in order: `task-001-…`, `task-002-…`. Use the next number after the highest one in `docs/archive/`.
2. **Mark what is being worked on:** exactly one item carries `**▶ IN PROGRESS**`. Move the marker before starting the next item, not after.
3. **Keep it current:** tick an item as soon as it is done, and add its commit hash to finished features. Add sub-tasks you discover along the way. Write anything the next agent needs to know under **Notes for the next agent**.
4. **Resume first:** an agent that finds an active task continues from the in-progress item and reads the notes before doing anything else. It does not start a new task until the current one is finished or the user drops it.
5. **Finish:** when every item is ticked, copy the whole section (checklist, commit hashes, notes) into `docs/archive/task-NNN-short-name-archive.md`. Add a finished date and a short summary of the outcome. Then reset **Current task** to `_No active task._` and commit both files in one `docs(archive): …` commit. The archive is the working history; never edit an archived file afterwards.

## Commit rules

- **One feature per unit of work.** Split a task into separate features (a fix, a refactor, a capability, a doc) and finish them one at a time. Don't mix unrelated changes in a single change set.
- **Commit as soon as a feature is complete.** When one feature is done and the checks pass, commit it before starting the next. Never batch several features into one commit, and never leave finished work uncommitted.
- **Each commit stands alone.** It builds, passes the checks, and contains only the files for that feature.
- **Message format:** Conventional Commits, `type(scope): summary`, in the imperative and lower case. For example, `fix(anki): read the connection state live instead of replaying a snapshot`. Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.
- Add a body when the reason isn't obvious from the summary.
