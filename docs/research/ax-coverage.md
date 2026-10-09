# Accessibility coverage per app

What macOS Accessibility returns for a selection in each of the 13 test apps, measured with `baron-probe`. This table decides which `SelectionContext` fields v1 promises plugins (task-001 gate).

Status: **in progress**: 1 of 13 apps measured (TextEdit, by an agent). The rest need a person, because each needs a real selection.

## How to measure an app

```sh
cd macos && swift build
.build/debug/baron-probe --delay 3          # switch to the app and select a word inside a sentence
.build/debug/baron-probe --delay 3 --copy   # same, also tries Edit › Copy and ⌘C (clipboard is restored)
```

Use `--json` to save the raw output. Select one word in the middle of a multi-sentence paragraph, so the sentence and paragraph results can be told apart.

Mark each field **✓** (correct), **~** (partly right: say how), or **✗** (missing). Write the slowest step's time in the last column.

## Results

| App | selected text | web selection | web sentence / paragraph | native window | native sentence / paragraph | page URL / title | window title / document | bounds | menu copy | ⌘C | slowest step |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TextEdit | ✓ | n/a | n/a | ✓ | ✓ / ✓ | n/a | ✓ / ✓ | ✓ native | not run | not run | 1.5 ms (native window) |
| Safari | | | | | | | | | | | |
| Chrome | | | | | | | | | | | |
| Arc | | | | | | | | | | | |
| Mail | | | | | | | | | | | |
| Notes | | | | | | | | | | | |
| Pages | | | | | | | | | | | |
| Preview | | | | | | | | | | | |
| Xcode | | | | | | | | | | | |
| VS Code | | | | | | | | | | | |
| Slack | | | | | | | | | | | |
| Obsidian | | | | | | | | | | | |
| Terminal | | | | | | | | | | | |

## Findings so far

- **TextEdit (2026-10-10):** every native field works. The selection was set through Accessibility on a background TextEdit window; reads took 0.2–1.5 ms each.
- **Copy fallback and clipboard managers:** SelectedTextKit saves and restores every clipboard item, but the copy is written by the source app. A clipboard manager that polls quickly may still record it; Baron can't mark that write as transient. To be confirmed with a clipboard manager running.

## Conclusions

To write once the table is filled: which context fields are reliable enough to promise in v1, and which apps need a per-app rule.
