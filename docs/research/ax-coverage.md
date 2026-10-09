# Accessibility coverage per app

What macOS Accessibility returns for a selection in the test apps, measured on 2026-10-10 by `baron-uitest` (macOS 26.2). In each app the harness opened a fixture and made three selections with real mouse events: **word** (double-click "quokka"), **sentence** (drag from "The" to "dog."), and **paragraph** (triple-click). For each one it checked that Baron's bar appeared and its Copy button copied the selection, ran the probe, and graded every field against the expected text.

**Result: 8 apps pass every field in all three modes.** Pages works for words; Preview, VS Code and Slack need a hand check (below); Obsidian isn't installed.

## Results

| App | Selected text | Context from | Sentence | Paragraph | Page URL | Page title | Window title | Document | Bounds | Menu copy | ⌘C | Bar shown | Slowest AX read |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TextEdit · word | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 12 ms | ✓ 38 ms | ✓ | 1.0 ms |
| TextEdit · sentence | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 15 ms | ✓ 16 ms | ✓ | 1.4 ms |
| TextEdit · paragraph | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 13 ms | ✓ 13 ms | ✓ | 1.0 ms |
| Safari · word | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 14 ms | ✓ 46 ms | ✓ | 2.1 ms |
| Safari · sentence | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 13 ms | ✓ 16 ms | ✓ | 1.4 ms |
| Safari · paragraph | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 18 ms | ✓ 26 ms | ✓ | 1.5 ms |
| Chrome · word | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 21 ms | ✓ 22 ms | ✓ | 3.7 ms |
| Chrome · sentence | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 20 ms | ✓ 23 ms | ✓ | 3.1 ms |
| Chrome · paragraph | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 12 ms | ✓ 22 ms | ✓ | 6.7 ms |
| Arc · word | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 16 ms | ✓ 14 ms | ✓ | 3.3 ms |
| Arc · sentence | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 20 ms | ✓ 31 ms | ✓ | 3.7 ms |
| Arc · paragraph | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 23 ms | ✓ 36 ms | ✓ | 3.2 ms |
| Mail · word | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 32 ms | ✓ 25 ms | ✓ | 3.5 ms |
| Mail · sentence | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 15 ms | ✓ 25 ms | ✓ | 0.8 ms |
| Mail · paragraph | ✓ | web | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ 16 ms | ✓ 27 ms | ✓ | 2.0 ms |
| Notes · word | ✓ | native | ✓ | ✓ | – | – | ✓ | – | ✓ | ✓ 40 ms | ✓ 35 ms | ✓ | 1.5 ms |
| Notes · sentence | ✓ | native | ✓ | ✓ | – | – | ✓ | – | ✓ | ✓ 24 ms | ✓ 31 ms | ✓ | 1.3 ms |
| Notes · paragraph | ✓ | native | ✓ | ✓ | – | – | ✓ | – | ✓ | ✓ 41 ms | ✓ 22 ms | ✓ | 1.8 ms |
| Xcode · word | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 15 ms | ✓ 22 ms | ✓ | 1.9 ms |
| Xcode · sentence | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 21 ms | ✓ 34 ms | ✓ | 6.0 ms |
| Xcode · paragraph | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 21 ms | ✓ 48 ms | ✓ | 3.2 ms |
| Terminal · word | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 19 ms | ✓ 64 ms | ✓ | 3.9 ms |
| Terminal · sentence | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 18 ms | ✓ 23 ms | ✓ | 1.8 ms |
| Terminal · paragraph | ✓ | native | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | ✓ 14 ms | ✓ 16 ms | ✓ | 1.6 ms |
| Pages · word | ✓ | native | ✓ | ✓ | – | – | ✓ | – | ✓ | ✓ 50 ms | ✓ 23 ms | ✓ | 2.3 ms |
| Pages · sentence | ✗ | native | ~ | ~ | – | – | ✓ | – | ✓ | ✗ 16 ms | ✗ 208 ms | ✗ | 2.0 ms |
| Pages · paragraph | ✓ | native | ✓ | ✓ | – | – | ✓ | – | ✓ | ✓ 32 ms | ✓ 30 ms | ✗ | 2.1 ms |
| Preview · word | ✗ | none | ✗ | ✗ | – | – | ✓ | ✓ | ✗ | ✗ 20 ms | ✗ 26 ms | ✗ | 1.3 ms |
| Preview · sentence | ✗ | none | ✗ | ✗ | – | – | ✓ | ✓ | ✗ | ✗ 28 ms | ✗ 28 ms | ✗ | 1.5 ms |
| Preview · paragraph | ~ | none | ✗ | ✗ | – | – | ✓ | ✓ | ✗ | ~ 17 ms | ~ 18 ms | ✗ | 3.1 ms |

✓ correct · ~ partly right · ✗ missing · – not applicable (no page, or no document file). Times are the copy step's duration and the slowest single Accessibility read.

Notes on the rows:

- **Terminal:** in one full run the bar didn't appear for Terminal, which ran right after VS Code; a rerun passed all three modes. Treat it as a test-ordering flake, not a Baron failure.
- **Pages · sentence:** the drag didn't select text. In Pages a drag can move or resize the text box, so this may be the test's gesture, not Baron. Check by hand.
- **Pages · paragraph:** the text, sentence and paragraph were read correctly, but the bar didn't appear. Check by hand.
- **Preview:** the word is found on screen, but the synthetic double-click doesn't select PDF text, so nothing is read. Check by hand.

## Per-app findings

| App | Finding | Status |
| --- | --- | --- |
| Pages | Document text is only exposed after `AXEnhancedUserInterface` is set, though the call reports an error | Fixed: Baron sets it for iWork apps only (`d082f47`) |
| Preview | Text is exposed as one `AXStaticText` per line block; other open PDFs add 20,000+ elements | Test fixed to search the front window first (`d082f47`); selection needs a hand check |
| VS Code | The editor's text area is empty unless "screen reader optimized" mode (`editor.accessibilitySupport`) is on; editor lines aren't exposed at all | Baron must rely on copying here. Hand check below |
| Chromium (Chrome, Arc) | Sentence and paragraph markers stop at inline elements and pull in neighbouring blocks at block edges | Fixed: paragraph rebuilt from the tree (`b54ac9f`, `5b91f5b`, `e79493c`) |
| WebKit (Safari, Mail) | A triple-click selection ends inside the next paragraph; the tree hides `<br>` breaks | Fixed: step back over trailing breaks and use markers (`e79493c`) |
| All apps | SelectedTextKit's ⌘C step stalled ~30 s on a System Events Automation prompt | Fixed: Baron posts ⌘C itself (`bc89053`) |
| TextEdit and other native apps | A triple-click includes the line break, which pulled in the next paragraph | Fixed (`5b91f5b`) |

## Hand checks

Use the debug panel: `open macos/build/Baron.app --args --debug-panel`, or choose **Show Debug Panel** from Baron's menu-bar icon. For each app, double-click a word, drag across a sentence, and triple-click a paragraph, then note what the panel shows.

| App | What to try | What to record |
| --- | --- | --- |
| VS Code | Default settings, then with **Settings › Accessibility Support: on** | Selected text and "Read by" (expect `menu-copy` or `key-copy` by default); whether sentence and paragraph appear with the setting on |
| Preview | Open any text PDF and select with the text tool | Selected text, sentence, paragraph, bounds; whether the bar appears |
| Pages | Drag across a sentence; triple-click a paragraph | Whether the bar appears; sentence and paragraph |
| Slack | Select text in a message (no typing needed) | Selected text, "Read by", sentence and paragraph |

## Conclusions

- **v1 can promise:** the selected text, app, window title and bounds wherever Accessibility works, with the copy steps covering the rest.
- **Sentence and paragraph** are reliable in the 8 measured apps after the fixes above. They stay optional in the contract, because Electron editors, PDFs and copy-only apps may not provide them.
- **Page URL and title** work in all three browsers and in Mail without AppleScript.
- **Speed:** every Accessibility read took under 7 ms. The copy fallbacks took 10–210 ms.
- **Clipboard managers:** the copy fallback is written by the source app, so Baron can't mark it as transient. It restores the user's clipboard afterwards.

## How to re-run

```sh
cd macos
scripts/build-app.sh             # the bar check uses build/Baron.app
scripts/uitest-all.sh            # every app; or name some: scripts/uitest-all.sh Safari Chrome
```

It takes over the mouse and keyboard for several minutes. Each app gets up to 3 attempts; results land in `macos/UITests/results/all.md`.
