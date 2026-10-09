# Baron (macOS)

Baron shows an action bar when text is selected in any app. Design: [docs/tec-design.md](../docs/tec-design.md). Plan: [docs/tasks.md](../docs/tasks.md).

## Layout

| Target | Role |
| --- | --- |
| `BaronCore` | Pure logic with no AppKit or Accessibility; covered by `swift test` |
| `BaronPlatform` | macOS glue: Accessibility, event monitors, pasteboard, windows |
| `Baron` | The menu-bar app |
| `baron-probe` | CLI that prints what the Accessibility API returns for the current selection |

## Build

```sh
swift build && swift test      # compile and run unit tests
scripts/build-app.sh           # build/Baron.app and build/baron-probe, signed
open build/Baron.app
```

`build-app.sh` signs with `BARON_SIGN_IDENTITY`, or the first "Apple Development" identity in your keychain. A stable signature keeps the Accessibility grant across rebuilds; ad-hoc builds lose it every time.

Baron and `baron-probe` both need **System Settings › Privacy & Security › Accessibility**. The probe runs inside your terminal, so grant the terminal app as well.

## Try the bar

```sh
scripts/build-app.sh && open build/Baron.app
```

Grant Baron Accessibility access when asked (or from its menu-bar icon), then select text in any app: drag, double-click, triple-click, ⇧-click, or ⇧-arrow / ⌘A. The bar offers Copy, Search and, when the selection holds a link, Open Link. The menu-bar icon has Pause and Settings (hotkey, search URL, excluded apps, launch at login).

Logs never contain selected text:

```sh
log stream --predicate 'subsystem == "org.odh.baron"'
```

## Measure Accessibility coverage

```sh
.build/debug/baron-probe --delay 3            # switch to an app and select text
.build/debug/baron-probe --app com.apple.TextEdit
.build/debug/baron-probe --delay 3 --copy --json
```

Record results in [docs/research/ax-coverage.md](../docs/research/ax-coverage.md).
