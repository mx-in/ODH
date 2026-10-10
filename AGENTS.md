# Agent guide

## Current task

**Task:** task-006-host-services: every host call, checked (gate: every host method rejects calls without its permission, and those needing a user action reject without one; the network matcher passes its corpus; run-time prompts work end to end in a UI test; contract tests pass on both engines)
**Started:** 2026-10-11 · **Agent:** Claude (Claude Code) · design: [03](docs/design/plugin-platform/03-host-api-and-ipc.md), [04](docs/design/plugin-platform/04-permissions-and-security.md)

- [ ] Permission model (BaronCore)
    - [x] Parse permission names and network patterns (715bfab)
    - [x] Match network patterns: hosts, subdomain wildcards, ports, schemes; private, link-local and loopback addresses only by an exact entry (715bfab)
    - [x] Share a network matcher corpus between `@baron/api` and Swift, and pass it in both (3ad0b12)
    - [ ] **▶ IN PROGRESS** Describe what each host method needs: a permission, a user action, or nothing
- [ ] Grants
    - [ ] Hold each plugin's granted set: install permissions plus saved run-time grants (Always Allow saved, Deny remembered 24 h, Allow Once in memory)
- [ ] User-action tracker
    - [ ] Record bar clicks per plugin, and reject side-effecting calls without one in the last 5 s
- [ ] Permission gate
    - [ ] Check every routed call before its service runs
- [ ] Network policy in `http.fetch`
    - [ ] Check the first URL and every redirect hop against the granted set, answering permission_denied with requestable
    - [ ] Resolve hosts before connecting, so a public name can't reach a private address
- [ ] Services
    - [ ] `clipboard.readText` and `clipboard.writeText`
    - [ ] `selection.replace` (only on an editable selection)
    - [ ] `text.segment` with `NLTokenizer`
    - [ ] `ui.openUrl` for `https`, `http` and `mailto`, and `ui.openSettings`
    - [ ] `permissions.query` and `permissions.request`
- [ ] Run-time prompt (UI)
    - [ ] Show the native prompt naming the plugin and host: Deny, Allow Once, Always Allow; one at a time
- [ ] Install sheet (UI, used by task-008)
    - [ ] Describe permissions in plain words, grouped as Reads, Connects to, Can and Stores, with the disclosures
    - [ ] Show them in a SwiftUI install sheet
- [ ] Contract tests
    - [ ] Call every method from JavaScript against Baron's router and against the mock host on both engines, from one shared corpus
- [ ] Verification
    - [ ] UI test of the prompt: Deny, Allow Once, Always Allow (revoking is tested in task-007)
- [ ] Design UML
    - [ ] Add as-built UML to 03 and 04

**Notes for the next agent:** Done in task-005 already: `http.fetch` basics (methods, headers, bodies, ephemeral session, 5 redirects) and private plugin log lines. Services that need AppKit or Accessibility (clipboard, replace, open URL, settings, prompts) go through protocols in BaronRuntime that the app implements, so BaronRuntime stays free of AppKit. Allow Once lasts 10 minutes in memory (the design leaves its scope open).

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

1. **Start:** before writing code, replace `_No active task._` with the task name, the start date, and a checklist that splits the task into features, with sub-tasks under each. End the checklist with a **Design UML** item (step 5). Number tasks in order: `task-001-…`, `task-002-…`. Use the next number after the highest one in `docs/archive/`.
2. **Mark what is being worked on:** exactly one item carries `**▶ IN PROGRESS**`. Move the marker before starting the next item, not after.
3. **Keep it current:** tick an item as soon as it is done, and add its commit hash to finished features. Add sub-tasks you discover along the way. Write anything the next agent needs to know under **Notes for the next agent**.
4. **Resume first:** an agent that finds an active task continues from the in-progress item and reads the notes before doing anything else. It does not start a new task until the current one is finished or the user drops it.
5. **Design UML** (user request 2026-10-10): when a task's work is done, add UML diagrams to every design doc the task built or changed, drawn from the result as built, not as planned. Use Mermaid: a `classDiagram` for the main types and how they relate, plus a `sequenceDiagram` or `stateDiagram-v2` for the main flow or lifecycle. Put them in a **UML** section at the end of the doc, before the gate. Update an existing diagram instead of adding a second one for the same thing, and fix the design text where the code differs from it. Commit as `docs(design): …`.
6. **Finish:** when every item is ticked, copy the whole section (checklist, commit hashes, notes) into `docs/archive/task-NNN-short-name-archive.md`. Add a finished date and a short summary of the outcome. Then reset **Current task** to `_No active task._` and commit both files in one `docs(archive): …` commit. The archive is the working history; never edit an archived file afterwards.

## Commit rules

- **One feature per unit of work.** Split a task into separate features (a fix, a refactor, a capability, a doc) and finish them one at a time. Don't mix unrelated changes in a single change set.
- **Commit as soon as a feature is complete.** When one feature is done and the checks pass, commit it before starting the next. Never batch several features into one commit, and never leave finished work uncommitted.
- **Each commit stands alone.** It builds, passes the checks, and contains only the files for that feature.
- **Message format:** Conventional Commits, `type(scope): summary`, in the imperative and lower case. For example, `fix(anki): read the connection state live instead of replaying a snapshot`. Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.
- Add a body when the reason isn't obvious from the summary.
