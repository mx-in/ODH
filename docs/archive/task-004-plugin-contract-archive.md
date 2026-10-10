# task-004-plugin-contract archive

**Finished:** 2026-10-10 · **Gate:** the JSON Schema and the Swift validator agree on 58 manifests; `when` rules and localisation are unit tested; ODH's manifest validates

**Summary:** `@baron/api` holds the plugin contract: manifest, context, host and error types, `definePlugin`, and a strict draft 2020-12 JSON Schema kept in step with the types by a test. BaronCore gained `ManifestValidator` (structure as the schema does it, then references, ranges and defaults, package paths, JavaScript-and-ICU regexes, API/Baron/platform compatibility, locale keys), `when` rule matching with a content classifier, and `PluginLocalizer`. A 58-case corpus shared by `bun test` and `swift test` holds the two checkers to the same JSON Pointers. ODH has its first Baron files: locales converted from `src/_locales` and a manifest covering every ODH option.

**Task:** task-004-plugin-contract: the manifest and types everything else builds on (gate: the JSON Schema and the Swift validator agree on 30+ manifests; `when` rules and localisation are unit tested; ODH's manifest validates)
**Started:** 2026-10-10 · **Agent:** Claude (Claude Code) · design: [01](docs/design/plugin-platform/01-package-and-manifest.md), types in [03](docs/design/plugin-platform/03-host-api-and-ipc.md)

- [x] Workspace
    - [x] Add `packages/*` as an npm workspace with an empty `@baron/api`, tested with Bun (c7fe921)
    - [x] Add the workspace's tests and type check to the checks in `AGENTS.md`
- [x] `@baron/api` types
    - [x] Write the manifest types, including every preference type (80d7035)
    - [x] Write `SelectionContext`, `TextSpan` and `ActionResult` (34428f8)
    - [x] Write `Host` and `ViewHandle` for apiVersion 1 (ee93ef9)
    - [x] Write `BaronError` and the error codes (59f425e)
    - [x] Write `definePlugin` (319f885)
- [x] Manifest JSON Schema
    - [x] Write the schema for the package fields and actions (0d3e736)
    - [x] Add the preference types to the schema (e9e7e7f)
    - [x] Test that the schema and the TypeScript types list the same fields (aecc8fb)
- [x] Manifest corpus
    - [x] Write the valid cases and the cases the schema rejects, each with its expected JSON Pointer (90f2d2d)
    - [x] Write the cases only the semantic checks reject, with their package files (7b3ddae)
    - [x] Run the corpus against the JSON Schema (90f2d2d)
- [x] Swift manifest model (BaronCore)
    - [x] Check a manifest's structure as the schema does, reporting JSON Pointers (63cdb3d)
    - [x] Decode a valid manifest into Swift types (9516f33)
    - [x] Check unique IDs, `dependsOn` targets, and that `needs` are granted (42c5e2e)
    - [x] Check ranges and defaults: minLength ≤ maxLength, a default within its options or range (found while writing the corpus) (c86f3e7)
    - [x] Check that paths stay inside the package and referenced files exist (bd552a2)
    - [x] Compile each `regex` as JavaScript and as ICU (0dec757)
    - [x] Check `apiVersion`, `minBaronVersion` and `platforms` (5ad0b00)
    - [x] Check that `%key%` strings exist in the default locale (abc30e8)
    - [x] Run the shared corpus in Swift tests (3d93f41)
- [x] `when` rules (BaronCore)
    - [x] Evaluate `minLength` and `maxLength` in UTF-16 units (f065c4b)
    - [x] Evaluate `regex` (e78fe26)
    - [x] Classify the text as `word`, `url`, `email`, `number` or `text` (17be52b)
    - [x] Evaluate `apps`, `excludeApps` and `editable` (cb36467)
- [x] Localisation (BaronCore)
    - [x] Resolve `%key%` strings through the preferred languages, then `defaultLocale`, then the key (f12ffb3)
- [x] ODH manifest
    - [x] Convert ODH's `_locales` into `plugins/odh/locales/` with a script and a test that keeps them in sync (ae61d3a)
    - [x] Write `plugins/odh/manifest.json` with the action, permissions and every preference (bf4423e)
- [x] Verification
    - [x] Check the gate
- [x] Design UML
    - [x] Replace the design-level UML in `01-package-and-manifest.md` with diagrams of the code as built (547970d)

**Notes for the next agent:** gate checked 2026-10-10: 58 corpus manifests give identical pointers in the JSON Schema (bun test) and ManifestValidator (swift test); when rules and the localizer are unit tested; plugins/odh/manifest.json validates in both. The JavaScript side is an npm workspace in the root `package.json` (one installer, one lockfile with ODH); Bun 1.4 runs the tests and, later, builds (installed with `npm install -g bun`). The corpus lives in `packages/api/test/corpus/` and is read by both `bun test` and the Swift tests. Pointer convention: an error points at the offending field; a missing or unknown field points at where that field is or would be.
