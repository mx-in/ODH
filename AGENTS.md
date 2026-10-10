# Agent guide

## Current task

**Task:** task-007-storage-and-settings: plugins keep data, users set options (gate: each store passes its unit tests; a test plugin shaped like ODH renders every preference type and fills its dropdowns from a mock AnkiConnect; list, checklist, button, secret and revoke work in a UI test.)
**Started:** 2026-10-11 · **Agent:** Claude (Claude Code) · design: [05 Storage](docs/design/plugin-platform/05-storage.md), [06 Settings](docs/design/plugin-platform/06-settings.md).

- [x] Data folders
    - [x] Create each plugin's data and cache folders (6538503)
- [x] Preferences store
    - [x] Save and load `preferences.json`, with defaults from the manifest (6538503)
- [x] Storage
    - [x] Store JSON values in SQLite, one actor per plugin (a500d9d)
    - [x] Enforce the 5 MB quota and 1 MB per value (a500d9d)
    - [x] Serve `host.storage` (a500d9d)
- [x] Cache
    - [x] Store strings in SQLite in the Caches folder, evicting the least recently read past 10 MB (064e74f)
    - [x] Serve `host.cache` (064e74f)
- [x] Secrets
    - [x] Keep secrets in the Keychain per plugin, not synchronisable (b5ad444)
    - [x] Serve `host.secrets` behind the `secrets` permission (b5ad444)
- [x] Data management
    - [x] Report usage; Clear cache; Reset plugin data (bb71fbf)
    - [x] Remove every store and grant of a plugin (used by uninstall) (bb71fbf)
- [ ] Settings: Plugins section (UI)
    - [ ] **▶ IN PROGRESS** List installed plugins with Enabled switches
    - [ ] Show a plugin's page: header, preferences, permissions, data, about
- [ ] Settings: preference controls (UI)
    - [ ] `text`, `number` and `checkbox`
    - [ ] `dropdown` and `checklist` with static options
    - [ ] `list` with add, remove and reorder
    - [ ] `secret`
    - [ ] `file`, `directory` and `app`
    - [ ] `button` with its result line, and `heading`
- [ ] Settings: options from the plugin
    - [ ] Call options providers with a spinner; show errors with Retry
    - [ ] Keep a saved value missing from new options, marked "not found"
    - [ ] Reload a field's options when a field in its `dependsOn` changes
- [ ] Settings: saving
    - [ ] Validate and save 0.5 s after the last edit; show inline errors
    - [ ] Refresh `host.preferences` before each dispatch, and reload a loaded plugin when they change
    - [ ] Open the settings page with empty required fields highlighted when an action needs them
- [ ] Settings: Permissions section
    - [ ] List run-time grants with Remove buttons
- [ ] Verification
    - [ ] Unit test each store: persistence across reload, quotas, per-value limits, eviction order; 1,000 writes and reads in under a second
    - [ ] UI test with the ODH-shaped plugin and a mock AnkiConnect, including revoking a grant
- [ ] Design UML
    - [ ] Add as-built UML to the design docs this task built or changed

**Notes for the next agent:** User request 2026-10-11: complete tasks 007 to 013 in order (not 014). Stores use the system SQLite (import SQLite3) and the Keychain; the settings UI is SwiftUI in the app target.

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
- [Baron Plugin Platform — Design](docs/design/plugin-platform/README.md): the plugin platform split into ten sub-projects (manifest, runtime, host API, permissions, storage, settings, web views, native views, tooling, install), each in its own file, with [ODH on Baron](docs/design/plugin-platform/odh-on-baron.md) as the success test. Read the sub-project's file before working on its task.
- [Task backlog](docs/tasks.md): the design split into tasks, features and sub-tasks. Start the next task from here.
- Extension background and development notes: [doc/](doc/).

## Checks

Run these before every commit:

```sh
npm run lint
npm run test:contracts
npm run test:unit
```

When `packages/` or `plugins/` changed, also run these (they need [Bun](https://bun.sh) 1.4 or later, for example `npm install -g bun`, and QuickJS-NG from `npm run tools:qjs`):

```sh
npm run test:baron
npm run typecheck:baron
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

1. **Start:** before writing code, replace `_No active task._` with the task name, the start date, and a checklist that splits the task into features, with sub-tasks under each. End the checklist with a **Design UML** item (step 6). Number tasks in order: `task-001-…`, `task-002-…`. Use the next number after the highest one in `docs/archive/`.
2. **Mark what is being worked on:** exactly one item carries `**▶ IN PROGRESS**`; blocked items carry `**⏸ BLOCKED**` instead (step 5). Move the marker before starting the next item, not after.
3. **Keep it current:** tick an item as soon as it is done, and add its commit hash to finished features. Add sub-tasks you discover along the way. Write anything the next agent needs to know under **Notes for the next agent**.
4. **Resume first:** an agent that finds an active task continues from the in-progress item and reads the notes before doing anything else. It does not start a new task until the current one is finished or the user drops it.
5. **Skip what is blocked, and keep going** (user request 2026-10-11): when an item is interrupted or needs a person (a locked screen, a permission dialog, a decision, a device, a credential), don't stop the task. Mark the item `**⏸ BLOCKED (needs: what, from whom)**`, write under **Notes for the next agent** what was tried, what is needed and how to resume, then move `**▶ IN PROGRESS**` to the next item that doesn't depend on it, and keep working.
    - Only skip what is really blocked: retry a flaky step first, and don't skip an item whose result later items need; skip those dependants too, and mark them the same way.
    - Come back to blocked items as soon as their need is met (for example, the screen is unlocked), before starting a new task.
    - Commit finished work as usual; a blocked item is never ticked, and a task with blocked items isn't archived.
    - When reporting to the user, list every blocked item with what it needs, so they can unblock it in one go.
6. **Design UML** (user request 2026-10-10): when a task's work is done, add UML diagrams to every design doc the task built or changed, drawn from the result as built, not as planned. Use Mermaid: a `classDiagram` for the main types and how they relate, plus a `sequenceDiagram` or `stateDiagram-v2` for the main flow or lifecycle. Put them in a **UML** section at the end of the doc, before the gate. Update an existing diagram instead of adding a second one for the same thing, and fix the design text where the code differs from it. Commit as `docs(design): …`.
7. **Finish:** when every item is ticked (none left blocked), copy the whole section (checklist, commit hashes, notes) into `docs/archive/task-NNN-short-name-archive.md`. Add a finished date and a short summary of the outcome. Then reset **Current task** to `_No active task._` and commit both files in one `docs(archive): …` commit. The archive is the working history; never edit an archived file afterwards.

## Commit rules

- **One feature per unit of work.** Split a task into separate features (a fix, a refactor, a capability, a doc) and finish them one at a time. Don't mix unrelated changes in a single change set.
- **Commit as soon as a feature is complete.** When one feature is done and the checks pass, commit it before starting the next. Never batch several features into one commit, and never leave finished work uncommitted.
- **Each commit stands alone.** It builds, passes the checks, and contains only the files for that feature.
- **Message format:** Conventional Commits, `type(scope): summary`, in the imperative and lower case. For example, `fix(anki): read the connection state live instead of replaying a snapshot`. Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.
- Add a body when the reason isn't obvious from the summary.
