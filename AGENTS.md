# Agent guide

## Current task

**Task:** task-005-runtime: run plugin code from the bar, in-process (gate: a sample plugin with an uppercase action and a `fetch`-based lookup runs from Baron's bar; its tests pass on JavaScriptCore and QuickJS-NG with the same prelude; timers, errors, time limits, idle unload and reload are tested)
**Started:** 2026-10-10 · **Agent:** Claude (Claude Code) · design: [02](docs/design/plugin-platform/02-runtime.md), [03](docs/design/plugin-platform/03-host-api-and-ipc.md), [09](docs/design/plugin-platform/09-developer-tooling.md) · user: "continue until the runtime task is completed, I'll check then"

- [x] Setup
    - [x] Fetch a pinned QuickJS-NG `qjs` into `.tools/` with a checksum-verified script (33a9991)
    - [x] Write the envelope types and codec in `@baron/api` (shared by prelude, harness and docs) (7644216)
- [x] Prelude (`@baron/runtime`)
    - [x] Build call envelopes and match results to calls by `id` (1ccd2cf)
    - [x] Build the `host` object over `__baronNative` (930e4b9)
    - [x] Serve dispatches: find the export, call it, await it, reply with a result or a classified error (5c7cce2)
    - [x] Provide `console`, the timer functions and `queueMicrotask` (a4fa8db)
    - [x] Polyfill `URL` and `URLSearchParams` (011a9b3)
    - [x] Polyfill `TextEncoder`, `TextDecoder`, `atob`, `btoa` and `structuredClone` (40abfeb)
    - [x] Polyfill `AbortController` and `AbortSignal`, and cancel a dispatch through its signal (46fb9d4)
    - [x] Provide `fetch`, `Request`, `Response` and `Headers` over `host.http` (ca9369d)
    - [x] Compile the prelude to one script, copied into the Swift runtime's resources with a sync test (2d7de23)
- [x] Engine contexts (Swift, new `BaronRuntime` target)
    - [x] Create one `JSVirtualMachine` and context per plugin, on its own serial queue (4afe0ed)
    - [x] Expose `__baronNative.send` and deliver envelopes back to the context (4447b2f)
    - [x] Back the timer functions with native timers on the plugin's queue (14c7632)
    - [x] Provide `crypto.getRandomValues`, `crypto.randomUUID` and `crypto.subtle.digest` (6f16fb1)
    - [x] Load the prelude and the bundle within 2 s, and mark a plugin that fails to load as broken (0304cdd)
    - [x] Enforce each dispatch's time limit and abort its signal (54cee8c)
    - [x] Disable a plugin stuck in a synchronous loop for 10 s, and one with 3 strikes in 10 minutes (53d9611)
    - [x] Unload a context after 60 s idle and load it again on the next need (192655a)
- [x] Host router (Swift)
    - [x] Decode envelopes and route `ns.method` to a service, returning the design's error codes (815a37c)
    - [x] Serve `log` and `ui.toast`; send `environment` and `preferences` (manifest defaults) with each dispatch (e21fc40)
    - [x] Serve `http.fetch` with its time and size limits (permission checks come in task-006) (87ccbca)
- [x] Bar integration
    - [x] Load plugins from the development folder (installing comes in task-008) (739a2bc)
    - [x] Show plugin actions whose `when` rules match, after the built-in ones (cf5120b)
    - [x] Dispatch a click with `text`, `source`, `editable`, `app` and `platform` (03d2b92)
    - [x] Carry out action results: copy, replace, toast, open URL (148a42e)
    - [x] Show a plugin's error as a toast naming the plugin (eb2fa5a)
- [x] Tooling
    - [x] `baron build`: bundle `src/` into one classic script with an inline source map (36f8f4f)
    - [x] `baron build` checks: manifest, Node built-ins, bundle size, `eval` without `code.dynamic` (ab14943)
    - [x] `@baron/test`: a mock host with in-memory services (97504fd)
    - [x] Run plugin tests on JavaScriptCore through `node:vm` (640803a)
    - [x] Run plugin tests on QuickJS-NG through `qjs`, with envelopes on standard input and output (29c4a95)
    - [x] `baron test --engine jsc|quickjs|all` (055eaa2)
- [x] Examples
    - [x] Write the uppercase action example with tests (76479df)
    - [x] Write the `fetch`-based lookup example with tests (316e545)
- [ ] Verification
    - [x] Test timers, errors, time limits, idle unload and reload (covered by TimerTests, PluginLoadingTests, DispatchTests, StuckPluginTests, IdleTests in BaronRuntimeTests, and the prelude's bun tests)
    - [x] Measure load time, dispatch overhead and idle memory against the targets in the design (ad419d4)
    - [ ] **▶ IN PROGRESS** Run both examples from the bar in a UI test
- [ ] Design UML
    - [ ] Replace the design-level UML in 02, 03 (core) and 09 with diagrams of the code as built

**Notes for the next agent:** QuickJS-NG `qjs` comes from `scripts/fetch-qjs.sh` (pinned v0.17.0, SHA-256 checked) into `.tools/`; the user hadn't answered whether to vendor it, so this is the default.

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
