# task-003-plugin-design archive

**Finished:** 2026-10-10 · **Gate:** the user approved the plugin platform design

**Summary:** Researched how Raycast, PopClip, VS Code, Obsidian, Figma, Zed and Alfred run plugins, and which JavaScript engines, UI approaches and storage fit Baron (`docs/research/plugin-runtime.md`). Designed the plugin platform as ten sub-projects with ODH on Baron as the success test (`docs/design/plugin-platform/`), re-planned the backlog as tasks 004–014, and, on the user's request, added a rule that every finished task adds UML to its design docs, starting with this design and the selection bar as built.

**Task:** task-003-plugin-design: research and design the plugin platform (gate: the user approves the design). Renamed from task-003-plugin-runtime when the runtime work was split into tasks 004–014.
**Started:** 2026-10-10 · **Agent:** Claude (Claude Code)

- [x] Research (user request 2026-10-10: runtime, storage, settings UI; look at Raycast and beyond)
    - [x] How Raycast runs extensions: runtime, process model, React-to-native UI, preferences, storage
    - [x] Other plugin systems: PopClip, VS Code, Obsidian, Figma, Zed, Alfred
    - [x] JS engines for plugins: JavaScriptCore, QuickJS-NG, Hermes, Node/Bun/Deno, WebAssembly
    - [x] Native UI from JS: React reconcilers rendering to SwiftUI/AppKit, declarative schemas, web views
    - [x] Storage and secrets: key-value, cache, Keychain
    - [x] Write the decision and update the design: `docs/research/plugin-runtime.md`, `docs/tec-design.md`, and the Claude Doc (f9b36ca, 23d6fbe)
- [x] Platform design (user request 2026-10-10: design runtime, UI, settings and the rest as separate sub-projects; success = ODH rewritten on Baron)
    - [x] Write the Claude Doc "Baron Plugin Platform — Design": overview, ten sub-projects, ODH on Baron (https://claude.ai/code/artifact/c7b7a984-f745-4ca3-b858-81419c79e35e)
    - [x] Mirror it in `docs/design/plugin-platform/` (fdeb2c6)
    - [x] Point the app design at it and give the proposed answers to its open questions (8a24023)
    - [x] Re-plan `docs/tasks.md` as tasks 004–014, one per sub-project, with gates from the design (d2a3423)
- [x] User reviews the platform design: approved 2026-10-10
- [x] Design UML (new rule, user request 2026-10-10; rule added in ddb8fb6)
    - [x] Add design-level UML to each plugin platform doc (nothing is built yet, so the diagrams show the design) (f87f951)
    - [x] Add UML of the selection bar as built in tasks 001–002 to `docs/tec-design.md` (f2a23fa)
    - [x] Record the approved answers to the plugin open questions (d3673d7)

**Notes for the next agent:** the platform design is approved. Next: task-004-plugin-contract from `docs/tasks.md`. The repo copies of the designs are the maintained ones; the Claude Docs are the approved snapshots and have no UML.
`npm run lint` fails in this checkout because `node_modules` isn't installed (a global ESLint 8.53 runs and can't read `eslint.config.mjs`); run `npm install` before relying on it.
