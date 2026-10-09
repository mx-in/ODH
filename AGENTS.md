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
- [ ] Coverage measurement (**blocked on the user**: needs real selections in each app)
    - [ ] Run the probe on the 13 test apps and record each field (TextEdit done by an agent)
    - [ ] Measure the time each retrieval step takes per app
    - [x] Write `docs/research/ax-coverage.md` (template, TextEdit row, how to measure)
    - [ ] Write the conclusions in `docs/research/ax-coverage.md`
- [ ] Design update (after the measurement)
    - [ ] Update the `SelectionContext` contract to match the measured coverage
    - [ ] Correct the design's claim that Baron marks the copy as transient: the source app writes it, so Baron can't

**Task:** task-002-selection-bar: the bar appears in any app (gate: the bar shows in every test app, or the gap is documented)
**Started:** 2026-10-10 · **Agent:** Claude (Claude Code) · runs while task-001 waits for the user

- [x] Selection monitor (commit 6d435a7)
    - [x] Detect mouse-up after a drag of 5 px or more
    - [x] Detect double- and triple-click
    - [x] Detect ⇧-click
    - [x] Detect ⇧-arrow and ⌘A, debounced 300 ms
    - [x] Record a window drag (window moved or resized between mouse-down and mouse-up)
- [x] Hotkey (commit: see next; no default shortcut, recorded in Settings)
    - [x] Add KeyboardShortcuts and record one configurable shortcut
    - [x] Send the hotkey trigger straight to retrieval, skipping the gate
- [ ] **▶ IN PROGRESS** Gate
    - [ ] Reject apps on the exclusion list, with the default list
    - [ ] Reject secure text fields and secure keyboard input
    - [ ] Reject roles that cannot hold text
    - [ ] Reject window drags
- [ ] Text retriever
    - [ ] Define the `TextRetriever` protocol
    - [ ] Wrap SelectedTextKit behind it
    - [ ] Apply a 0.5 s timeout to every AX call (done in `AXElement`; check SelectedTextKit's calls)
    - [ ] Retry the web step up to 6 times within 300 ms
    - [ ] Choose the chain's starting step from per-app rules
- [ ] Action bar window
    - [ ] Show a non-activating `NSPanel` that never takes focus
    - [ ] Position it above the selection, or below near the top of the screen; fall back to the mouse position
    - [ ] Close it on an outside click, key press, scroll or app switch
    - [ ] Render action buttons from a list of actions
- [ ] Built-in actions
    - [ ] Copy
    - [ ] Search with a configurable URL template
    - [ ] Open a link found in the selection
- [ ] Settings
    - [ ] Pause and resume the bar from the menu-bar item
    - [ ] Edit the excluded apps
    - [ ] Launch at login
- [ ] Logging
    - [ ] Log text length and the retrieval step used, never the text
- [ ] Verification (needs the user)
    - [ ] Run the bar on the 13 test apps and record the results in `docs/research/ax-coverage.md`

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
