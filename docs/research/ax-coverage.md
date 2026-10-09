# Accessibility coverage per app

What macOS Accessibility returns for a selection in the test apps, measured on 2026-10-10 by `baron-uitest` (macOS 26.2). In each app the harness opened a fixture, double-clicked the word "quokka" with real mouse events, checked that Baron's bar appeared and that its Copy button copied the word, ran the probe, and graded every field against the expected sentence and paragraph.

**Result: 8 of 13 apps pass every column.** Three apps couldn't be measured automatically, Slack was skipped on purpose, and Obsidian isn't installed.

## Results

| App | Selected text | Context from | Sentence | Paragraph | Page URL | Page title | Window title | Document | Bounds | Menu copy | ⌘C | Bar shown | Slowest AX read |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TextEdit | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 13 ms | ✓ 54 ms | ✓ | 2.2 ms |
| Safari | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 10 ms | ✓ 50 ms | ✓ | 0.4 ms |
| Chrome | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 12 ms | ✓ 38 ms | ✓ | 2.6 ms |
| Arc | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 26 ms | ✓ 58 ms | ✓ | 2.4 ms |
| Mail | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 29 ms | ✓ 53 ms | ✓ | 2.3 ms |
| Notes | ✓ | native | ✓ | ✓ | – | – | ✓ | – | ✓ | ✓ 20 ms | ✓ 31 ms | ✓ | 1.7 ms |
| Xcode | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 15 ms | ✓ 43 ms | ✓ | 2.3 ms |
| Terminal | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 21 ms | ✓ 82 ms | ✓ | 4.3 ms |

✓ correct · ~ partly right · ✗ missing · – not applicable (no page, or no document file). The bar's Copy button copied "quokka" in all 8 apps.

**Not measured:**

| App | Why |
| --- | --- |
| Pages | The harness couldn't find the word in the Accessibility tree after 3 attempts |
| Preview | Same; the PDF's text may not be exposed as element values |
| VS Code | Same; the editor (Monaco) may expose text only through a hidden text area |
| Slack | Skipped: testing would mean typing into a real workspace. Test by hand |
| Obsidian | Not installed |

For these, the harness's word finder failed, not necessarily Baron. Check them by hand with `baron-probe --delay 3`.

## What the runs found and fixed

- **⌘C fallback stalled for ~30 s.** SelectedTextKit's shortcut strategy mutes the alert sound by scripting System Events, which raises an Automation prompt. Baron now posts ⌘C itself (`bc89053`).
- **Chromium returned only the word as its sentence and paragraph**, and no bounds, when the word sat in its own inline element. Baron now rebuilds the paragraph from the Accessibility tree and uses the text element's frame (`b54ac9f`). Safari didn't need this.
- **Safari's web area has no title.** Baron falls back to the window title (`b54ac9f`).

## Conclusions

- **v1 can promise:** the selected text, app, window title, and selection bounds in all measured apps. The bar appeared in every one.
- **Sentence and paragraph** worked in every measured app (web or native path). They stay optional in the contract, because copy-only apps and the unmeasured apps may not provide them.
- **Page URL and title** work in all three browsers and Mail without AppleScript.
- **Speed:** every Accessibility read took under 5 ms. The copy fallbacks took 10–82 ms, well within the 150 ms budget for showing the bar.
- **Clipboard managers:** the copy fallback is written by the source app, so Baron can't mark it as transient. It does restore the user's clipboard. Not yet tested with a clipboard manager running.

## How to re-run

```sh
cd macos
scripts/build-app.sh             # the bar check uses build/Baron.app
scripts/uitest-all.sh            # every app; or name some: scripts/uitest-all.sh Safari Chrome
```

It takes over the mouse and keyboard for a few minutes. Each app gets up to 3 attempts; results land in `macos/UITests/results/all.md`.
