# task-006-host-services archive

**Finished:** 2026-10-11 · **Gate:** every host method rejects calls without its permission or required click; the network matcher passes its corpus; run-time prompts work end to end in a UI test; contract tests pass on both engines

**Summary:** Every host call now passes a permission gate: the method's permission from the plugin's granted set (install permissions plus Always Allow, Deny for a day, Allow Once for 10 minutes), then a click within 5 s for side effects. `http.fetch` checks each URL and redirect against network permissions and refuses public names that resolve to private addresses. New services: clipboard, selection.replace, text.segment, ui.openUrl and openSettings, and permissions.query and request with a native one-at-a-time prompt. Permissions are described in plain words for the prompt and an install sheet that task-008 will use. A shared contract corpus holds Baron's router and @baron/test's mock host to the same answers on both engines.

**Task:** task-006-host-services: every host call, checked (gate: every host method rejects calls without its permission, and those needing a user action reject without one; the network matcher passes its corpus; run-time prompts work end to end in a UI test; contract tests pass on both engines)
**Started:** 2026-10-11 · **Agent:** Claude (Claude Code) · design: [03](docs/design/plugin-platform/03-host-api-and-ipc.md), [04](docs/design/plugin-platform/04-permissions-and-security.md)

- [x] Permission model (BaronCore)
    - [x] Parse permission names and network patterns (715bfab)
    - [x] Match network patterns: hosts, subdomain wildcards, ports, schemes; private, link-local and loopback addresses only by an exact entry (715bfab)
    - [x] Share a network matcher corpus between `@baron/api` and Swift, and pass it in both (3ad0b12)
    - [x] Describe what each host method needs: a permission, a user action, or nothing (2d4bd5f)
- [x] Grants
    - [x] Hold each plugin's granted set: install permissions plus saved run-time grants (Always Allow saved, Deny remembered 24 h, Allow Once in memory) (27a0bdf)
- [x] User-action tracker
    - [x] Record bar clicks per plugin, and reject side-effecting calls without one in the last 5 s (f1a9750)
- [x] Permission gate
    - [x] Check every routed call before its service runs (a8bae3f)
- [x] Network policy in `http.fetch`
    - [x] Check the first URL and every redirect hop against the granted set, answering permission_denied with requestable (e34bc99)
    - [x] Resolve hosts before connecting, so a public name can't reach a private address (9b6e418)
- [x] Services
    - [x] `clipboard.readText` and `clipboard.writeText` (aa56d94)
    - [x] `selection.replace` (only on an editable selection) (8520008)
    - [x] `text.segment` with `NLTokenizer` (8520008)
    - [x] `ui.openUrl` for `https`, `http` and `mailto`, and `ui.openSettings` (ab649f3)
    - [x] `permissions.query` and `permissions.request` (b49d1b1)
- [x] Run-time prompt (UI)
    - [x] Show the native prompt naming the plugin and host: Deny, Allow Once, Always Allow; one at a time (c303971)
- [x] Install sheet (UI, used by task-008)
    - [x] Describe permissions in plain words, grouped as Reads, Connects to, Can and Stores, with the disclosures (179a710)
    - [x] Show them in a SwiftUI install sheet (a546e6d; its look is checked with the prompt UI test: open Baron with --preview-install-sheet plugins/odh)
- [x] Contract tests
    - [x] Call every method from JavaScript against Baron's router and against the mock host on both engines, from one shared corpus (6139825)
- [x] Verification
    - [x] UI test of the prompt: Deny, Allow Once, Always Allow (revoking is tested in task-007) (2b8f2af)
- [x] Design UML
    - [x] Add as-built UML to 03 and 04 (c69b9b9)

**Notes for the next agent:** Gate checked 2026-10-11: the gate refuses missing permissions and clicks (PermissionGateTests); both matchers pass network-corpus.json; the prompt UI test passed all 7 checks (macos/scripts/uitest-permissions.sh); the host contract passes against Baron's router and the mock host on both engines. Found and fixed on the way: log lines could arrive out of order (57db612), and NLTokenizer counted emoji as words (0a71313). Done in task-005 already: `http.fetch` basics (methods, headers, bodies, ephemeral session, 5 redirects) and private plugin log lines. Services that need AppKit or Accessibility (clipboard, replace, open URL, settings, prompts) go through protocols in BaronRuntime that the app implements, so BaronRuntime stays free of AppKit. Allow Once lasts 10 minutes in memory (the design leaves its scope open).
