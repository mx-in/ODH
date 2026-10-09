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
