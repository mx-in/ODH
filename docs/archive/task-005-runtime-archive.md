# task-005-runtime archive

**Finished:** 2026-10-10 · **Gate:** a sample plugin with an uppercase action and a `fetch`-based lookup runs from Baron's bar; its tests pass on JavaScriptCore and QuickJS-NG with the same prelude; timers, errors, time limits, idle unload and reload are tested

**Summary:** Plugins run in-process (stage 1). `@baron/runtime` is the prelude: host object, dispatching, timers, console and the web-platform subset, identical on every engine. `BaronRuntime` gives each plugin its own JavaScriptCore context and queue, with load and dispatch limits, stuck-plugin suspension, strikes and idle unload, and routes host calls to `log`, `ui.toast` and `http.fetch`. The bar shows plugin actions whose `when` rules match and carries out their results. `baron build` and `baron test`, `@baron/test`'s mock host and its JavaScriptCore and QuickJS-NG runners, and two examples complete it. Measured on an M1 Pro: 7 ms to load a 200 KB bundle, 0.08 ms per dispatch, about 2 MB per idle context.

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
- [x] Verification
    - [x] Test timers, errors, time limits, idle unload and reload (covered by TimerTests, PluginLoadingTests, DispatchTests, StuckPluginTests, IdleTests in BaronRuntimeTests, and the prelude's bun tests)
    - [x] Measure load time, dispatch overhead and idle memory against the targets in the design (ad419d4)
    - [x] Run both examples from the bar in a UI test (8ac455c; passed twice on 2026-10-10 after fixes 1389428 and e9faf46: UPPERCASE replaced the word in a Safari text area, Define showed Youdao's definition)
- [x] Design UML
    - [x] Replace the design-level UML in 02, 03 (core) and 09 with diagrams of the code as built (6fdad68)

**Notes for the next agent:** QuickJS-NG `qjs` comes from `scripts/fetch-qjs.sh` (pinned v0.17.0, SHA-256 checked) into `.tools/`. The bar UI test is `macos/scripts/uitest-plugins.sh`; it needs an unlocked screen. It uses Safari because TextEdit didn't open documents in this session. The lookup example uses dict.youdao.com because api.dictionaryapi.dev was unreachable from the user's network.
