# Agent guide

## Current task

**Task:** task-008-install: install, update and remove plugins (gate: install from a folder and a `.baronplugin` file, including refused cases; an update that adds a permission waits for consent; disable, enable and uninstall work, leaving nothing on disk or in the Keychain; a bundled sample is offered at first launch; bar settings pass a UI test; a first-time author gets from `baron create` to their action on the bar in under 2 minutes.)
**Started:** 2026-10-11 · **Agent:** Claude (Claude Code) · design: [10 Install and lifecycle](docs/design/plugin-platform/10-install-and-lifecycle.md), install consent in [04](docs/design/plugin-platform/04-permissions-and-security.md#install-and-update-consent), the CLI and development mode in [09](docs/design/plugin-platform/09-developer-tooling.md).

- [x] Package reading
    - [x] Read a plugin folder (ba394ce)
    - [x] Unzip a `.baronplugin`: files only, no symlinks, at most 50 MB (ba394ce)
- [x] Install
    - [x] Refuse an invalid manifest, an unsupported `apiVersion`, a newer `minBaronVersion` or an excluded platform, with the reason (ba394ce)
    - [x] Show the install sheet, warning when the same `id` comes from another source (7024c33)
    - [x] Copy the package to `Plugins/<id>/<version>/` (329c3a2)
    - [x] Run `onInstall` with a 10 s limit and show a failure (7024c33)
- [x] States
    - [x] Track Enabled, Disabled, Needs consent, Broken and Suspended (7024c33)
    - [x] Disable, enable, and re-enable a suspended plugin (7024c33)
- [x] Updates
    - [x] Treat a higher version as an update; ask before installing a lower or equal one (329c3a2)
    - [x] Install silently with the same or fewer permissions; with new ones, wait in Needs consent while the old version keeps working (329c3a2)
    - [x] Run `onUpdate` before the first dispatch, and delete the previous version after the first successful load (7024c33)
- [x] Uninstall
    - [x] Confirm, then remove the package and all of its data (7024c33)
- [x] Sources
    - [x] Add from Folder… in Settings (7024c33)
    - [x] Open `.baronplugin` files (7024c33)
    - [x] Handle `baron://install?url=https://…` (7024c33)
    - [x] Offer bundled plugins at first launch (7024c33)
- [x] Bar settings (UI)
    - [x] Reorder actions by drag, with new ones at the end (b805bfc)
    - [x] Show or hide each action (b805bfc)
    - [x] Run on selection for `autoRun: "allowed"` actions, optionally limited to some apps (b805bfc)
    - [x] Give an action its own hotkey (b805bfc)
- [x] Development mode
    - [x] Turn it on in Settings › Advanced and listen on a same-user socket (1221865)
    - [x] Load a registered folder as "Development" and reload it on each rebuild (1221865)
    - [x] Stream logs and errors with TypeScript line numbers; make contexts inspectable (1f51ad1)
- [x] CLI
    - [x] `baron create` with the `action`, `lookup` and `settings` templates (1f51ad1)
    - [x] `baron dev` (1f51ad1)
    - [x] `baron validate`, and `baron pack` printing the SHA-256 (1f51ad1)
- [ ] Verification
    - [x] Check the gate, including disk and Keychain after uninstall (18ba67e)
    - [ ] **⏸ BLOCKED (needs: an unlocked screen)** Time a first-time author from `baron create` to the action on the bar
- [x] Design UML
    - [x] Add as-built UML to the design docs this task built or changed

**Notes for the next agent:** Author timing (2026-10-11): `macos/scripts/uitest-author.sh` measured `baron create` 0.2 s, `npm install` 1.8 s and `baron dev` loading in Baron at 2.8 s; the last step, the action on the bar in Safari, stopped because the screen locked. Rerun the script with the screen unlocked and tick the item if the total is under two minutes. The install gate passes: `macos/scripts/uitest-install.sh`, 11 of 11 checks. Installed plugins live in Application Support/Baron/Plugins/<id>/<version>/ with a registry (installed.json); development-folder plugins keep working alongside. Archives are unpacked with the system unzip after listing their entries. @baron/* packages aren't on npm yet, so baron create links them with file: paths to this repository's packages/.


---

**Task:** task-009-context-builder: give actions the context they may read (gate: a test plugin receives sentence, paragraph, page and window in Safari, Chrome, Mail, Notes, Pages and TextEdit, and receives none of them without the permission.)
**Started:** 2026-10-11 · **Agent:** Claude (Claude Code) · design: [Context capture](docs/tec-design.md#context-capture) in the app design, context permissions in [04](docs/design/plugin-platform/04-permissions-and-security.md#permission-catalogue), `needs` in [01](docs/design/plugin-platform/01-package-and-manifest.md#actions). The readers from tasks 001 and 002 already exist; this task turns them into each action's `SelectionContext`.

- [ ] **▶ IN PROGRESS** Assembly
    - [ ] Build a `SelectionContext` from the existing readers
    - [ ] Read only the fields that some matching action `needs` and its plugin is granted
    - [ ] Give each action only its own `needs` and granted fields
- [ ] Timing
    - [ ] Read context in the background right after the text, within 200 ms; an action waits at most 300 ms more
    - [ ] Wake Chrome and Electron accessibility only for the frontmost app, and only when a field needs it
- [ ] Fields
    - [ ] Apply the caps and the `truncated` flag on the web paths, as the native path already does
    - [ ] Check that every offset is in UTF-16 units
    - [ ] Fall back to AppleScript for the page URL, behind a user setting
    - [ ] Read the sentence and paragraph from Preview's PDF text blocks (gap from task-001)
- [ ] Verification
    - [ ] Run the test plugin in the six apps in `baron-uitest`, with and without the permissions
- [ ] Design UML
    - [ ] Add as-built UML to the design docs this task built or changed

**Notes for the next agent:** Started while task-008 waits on one blocked item (author timing needs an unlocked screen); finish that item first when the screen is available, then archive task-008.

<!--
Template while a task is active (replace the line above):

**Task:** task-NNN-short-name: one-line goal
**Started:** YYYY-MM-DD · **Agent:** who is working on it

- [x] Feature 1: done (commit abc1234)
- [ ] Feature 2: what is being built
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
