# task-001-spike archive

**Finished:** 2026-10-10 · **Gate:** coverage table reviewed and approved by the user

**Summary:** Baron's Swift package, signed app bundle and Accessibility prompt exist, with `baron-probe` to read every field and `baron-uitest` to drive real apps. Measured with word, sentence and paragraph selections: TextEdit, Safari, Chrome, Arc, Mail, Notes, Xcode and Terminal pass every field; Pages passes by hand; VS Code and Preview give text without context; Slack was skipped. The runs found and fixed a ⌘C stall, Chromium and WebKit context bugs, a paragraph spill, Pages' hidden tree, and a crash outside web pages. The design now documents per-engine reading and the v1 field guarantees. Results: [docs/research/ax-coverage.md](../research/ax-coverage.md).

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
- [x] Coverage measurement (automated with `baron-uitest`; commits 4a5a8b4, 8824d00, 6579c24, 2588186, edcb838, e481c50)
    - [x] Move the probe's reading logic into `BaronPlatform` so the CLI and UI tests share it
    - [x] Grade a probe report against the fixture's expected text (`BaronCore`, unit tested)
    - [x] Add input automation and `baron-uitest` with word, sentence and paragraph modes
    - [x] Run the test apps: 8 apps pass every field in all three modes; Pages passes for words
    - [x] Fix what the runs found (bc89053, b54ac9f, 5b91f5b, e79493c, d082f47)
    - [x] Write the table and conclusions in `docs/research/ax-coverage.md`
    - [x] Hand checks by the user: Pages ✓; VS Code text ✓ via copy, no context (expected); Preview text ✓, no context (gap); Slack not checked
    - [x] Fix the crash the hand checks found in Alacritty, PDF Expert and Preview (retry() under the web step)
    - [x] User re-checks Alacritty, PDF Expert and Preview with the fixed build: no crash (2026-10-10)
    - [x] Read sentence and paragraph from Preview's PDF text blocks: moved to task-004 (context builder)
    - [x] Measure time from trigger to bar per app: warm 41–110 ms, first selection in an app 105–204 ms (commits: perf + test, see log)
    - [x] Grade the app Baron detects itself, not the one the test names: matched in all 23 selections
    - [x] Check the copy fallback with a clipboard manager running: user confirmed OK (2026-10-10); Slack skipped by the user
- [x] Design update
    - [x] Correct the design's claim that Baron marks the copy as transient (95c454b)
    - [x] Update "Context capture" with the per-engine methods: Chromium tree, WebKit markers, iWork wake-up, VS Code without editor text (commit: see next)
    - [x] Add the `AXEnhancedUserInterface` side effect to the risks
    - [x] Write the `SelectionContext` decision into the design: which fields v1 promises, which stay optional
- [x] Gate: the user reviewed and approved the coverage table (2026-10-10)

**Notes for the next agent:** coverage is measured by `macos/scripts/uitest-all.sh` (drives the mouse; see `docs/research/ax-coverage.md`). Hand checks use the debug panel: `open macos/build/Baron.app --args --debug-panel`. The user approved working on task-002 while task-001 waits for them.
