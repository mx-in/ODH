# 01 · Plugin package and manifest

Part of the [Baron Plugin Platform design](README.md).

A plugin is a folder with `manifest.json` at its root. The manifest says what the plugin is, which actions it adds to the bar, what it needs, and what users can set, and Baron reads all of it without running any plugin code.

**Scope.** In: the package layout, every manifest field, the JSON Schema and the Swift validator, `when` rules, localisation, versioning. Out: rendering preferences ([06](06-settings.md)), installing packages ([10](10-install-and-lifecycle.md)).

## Package layout

```text
org.odh.dictionary/
  manifest.json            required
  dist/main.js             required: the bundled plugin code (built by `baron build`)
  views/                   optional: web pages and their assets (07)
  assets/icon.svg          optional: icons, SVG only
  locales/en.json          optional: translated strings, one file per language
  locales/zh-Hans.json
  README.md, LICENSE       optional
```

During development the package is a plain folder. To share it, `baron pack` zips it as `<id>-<version>.baronplugin`.

## Manifest

```json
{
  "$schema": "https://baron.dev/schema/manifest-1.json",
  "id": "org.odh.dictionary",
  "name": "%name%",
  "description": "%description%",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "ODH contributors",
  "homepage": "https://github.com/ninja33/ODH",
  "license": "MIT",
  "defaultLocale": "en",
  "main": "dist/main.js",
  "icon": "assets/icon.svg",
  "platforms": ["macos", "windows", "linux"],
  "permissions": ["context.sentence", "context.page", "network:127.0.0.1:8765", "secrets"],
  "optionalPermissions": ["network:*"],
  "preferences": [ { "id": "deck", "type": "dropdown", "title": "%pref.deck%", "optionsFrom": "decks" } ],
  "actions": [
    {
      "id": "lookup",
      "title": "%action.lookup%",
      "icon": "assets/lookup.svg",
      "when": { "maxLength": 64, "contentTypes": ["word", "text"] },
      "needs": ["sentence", "page"],
      "autoRun": "allowed"
    }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | Yes | Reverse-DNS, lowercase, unique. Never changes between versions |
| `name`, `description` | Yes | Shown in Settings and at install; may be `%key%` references to `locales/` |
| `version` | Yes | Semantic version; a higher version is an update |
| `apiVersion` | Yes | The host API generation the plugin targets; currently `1` |
| `author`, `homepage`, `license` | No | Shown at install |
| `defaultLocale` | If `%key%` is used | The language used when the user's isn't available |
| `main` | Yes | The bundled code, relative to the package |
| `icon` | No | SVG; also the default action icon |
| `platforms` | No | Defaults to all three; a host refuses a plugin that excludes it |
| `minBaronVersion` | No | Refuse to install on older Baron |
| `permissions` | No | Granted at install ([04](04-permissions-and-security.md)) |
| `optionalPermissions` | No | Asked for at run time ([04](04-permissions-and-security.md)) |
| `preferences` | No | Settings Baron draws ([06](06-settings.md)) |
| `settingsPage` | No | A web page shown under the generated settings ([07](07-web-views.md)) |
| `settingsView` | No | Reserved for a native settings view ([08](08-native-views.md), after ODH) |
| `actions` | Yes, at least one | Buttons on the bar |

## Actions

| Field | Meaning |
| --- | --- |
| `id` | Unique within the plugin; also the exported handler's name unless `run` says otherwise |
| `run` | The handler's export name, if different from `id` |
| `title` | Button label (tooltip when the bar shows icons only) |
| `icon` | SVG in the package; falls back to the plugin icon |
| `when` | Rules that decide whether the button appears (below) |
| `needs` | Context the handler reads: any of `sentence`, `paragraph`, `page`, `window`. Each must also be granted as a permission. Baron reads only what some matching action needs, so selections stay fast |
| `autoRun` | `"allowed"` lets the user switch this action to run straight after a selection instead of showing a button. Off by default; only for actions without side effects, such as lookups |

## `when` rules

Baron checks these in Swift for every selection, before loading any plugin. All rules must hold; a missing rule doesn't constrain.

| Rule | Type | Holds when |
| --- | --- | --- |
| `minLength`, `maxLength` | integer | The trimmed text's length, in UTF-16 units, is within bounds |
| `regex` | string | The trimmed text matches. ECMAScript syntax; the validator rejects patterns that don't compile in both JavaScript and ICU |
| `contentTypes` | array | The text is one of: `word` (one word, letters only), `url`, `email`, `number`, `text` (anything) |
| `apps`, `excludeApps` | array | The source app is (not) listed. Entries are bundle IDs, or `{ "macos": "…", "windows": "…" }` |
| `editable` | boolean | The selection can be replaced |

## Localisation

Any string field may be `%key%`. Baron looks the key up in `locales/<language>.json`, a flat key-to-string map, trying the user's preferred languages in order (BCP 47, so `zh-Hans` for Simplified Chinese), then `defaultLocale`, then shows the key itself. Plugin code reads the language from `host.environment.locale` and translates its own UI.

## Validation

- **One schema, two checkers.** `@baron/api` publishes the JSON Schema (draft 2020-12). Baron's Swift validator decodes the same manifest and adds checks a schema can't express.
- **Checks beyond the schema:** action and preference IDs are unique; every permission name is known; `regex` compiles in both dialects; every path stays inside the package (no `..`, no symlinks out); icons are SVG; `%key%` references exist in `defaultLocale`.
- **Errors name the field** with a JSON Pointer (`/actions/0/when/regex`), in Baron's install sheet and in `baron build`.

## Versioning

`apiVersion` is a whole number. Baron runs plugins targeting the current and the previous number and refuses newer ones with a clear message. Any change to a manifest field's meaning, a host method, or the render-tree format starts a new number.

## Interfaces

The runtime ([02](02-runtime.md)) loads `main`; permissions ([04](04-permissions-and-security.md)) read `permissions` and `optionalPermissions`; settings ([06](06-settings.md)) render `preferences`; web views ([07](07-web-views.md)) serve `views/`; tooling ([09](09-developer-tooling.md)) generates and validates manifests; install ([10](10-install-and-lifecycle.md)) reads `id`, `version`, `platforms`, `minBaronVersion`.

## Risks

- **Regex dialects differ** between JavaScript and ICU. The validator compiles each `regex` in both and the shared test corpus covers common patterns.
- **The manifest grows.** New fields are optional, and anything that changes meaning waits for the next `apiVersion`.

## Gate (task-004)

- [ ] The JSON Schema and the Swift validator agree on a corpus of at least 30 valid and invalid manifests
- [ ] `when` rules are unit tested in Swift, including each content type and regex edge case
- [ ] Localised titles resolve for English and Simplified Chinese
- [ ] ODH's manifest is written and validates
