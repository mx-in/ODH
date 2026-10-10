# task-007-storage-and-settings archive

**Finished:** 2026-10-11 · **Gate:** each store passes its unit tests; a test plugin shaped like ODH renders every preference type and fills its dropdowns from a mock AnkiConnect; list, checklist, button, secret and revoke work in a UI test (all twelve checks of baron-uitest --settings pass)

**Summary:** Plugins keep data in four stores: preferences.json over the manifest's defaults, SQLite storage (5 MB, 1 MB per value) and cache (10 MB, least recently read evicted), and Keychain secrets on this device only; a data manager reports usage, clears, resets and removes everything for uninstall. Settings gained a Plugins tab: Enabled switches and a page per plugin with every preference type, options loaded from the plugin and reloaded on dependencies, buttons, validation with saving after 0.5 s, secrets, permissions with removable grants, and data. Actions use the saved values, and an empty required field opens the settings first. Fixed on the way: missing keys read as null instead of undefined.

**Task:** task-007-storage-and-settings: plugins keep data, users set options (gate: each store passes its unit tests; a test plugin shaped like ODH renders every preference type and fills its dropdowns from a mock AnkiConnect; list, checklist, button, secret and revoke work in a UI test.)
**Started:** 2026-10-11 · **Agent:** Claude (Claude Code) · design: [05 Storage](docs/design/plugin-platform/05-storage.md), [06 Settings](docs/design/plugin-platform/06-settings.md).

- [x] Data folders
    - [x] Create each plugin's data and cache folders (6538503)
- [x] Preferences store
    - [x] Save and load `preferences.json`, with defaults from the manifest (6538503)
- [x] Storage
    - [x] Store JSON values in SQLite, one actor per plugin (a500d9d)
    - [x] Enforce the 5 MB quota and 1 MB per value (a500d9d)
    - [x] Serve `host.storage` (a500d9d)
- [x] Cache
    - [x] Store strings in SQLite in the Caches folder, evicting the least recently read past 10 MB (064e74f)
    - [x] Serve `host.cache` (064e74f)
- [x] Secrets
    - [x] Keep secrets in the Keychain per plugin, not synchronisable (b5ad444)
    - [x] Serve `host.secrets` behind the `secrets` permission (b5ad444)
- [x] Data management
    - [x] Report usage; Clear cache; Reset plugin data (bb71fbf)
    - [x] Remove every store and grant of a plugin (used by uninstall) (bb71fbf)
- [x] Settings: Plugins section (UI)
    - [x] List installed plugins with Enabled switches (dae5b22)
    - [x] Show a plugin's page: header, preferences, permissions, data, about (dae5b22)
- [x] Settings: preference controls (UI)
    - [x] `text`, `number` and `checkbox` (dae5b22)
    - [x] `dropdown` and `checklist` with static options (dae5b22)
    - [x] `list` with add, remove and reorder (dae5b22)
    - [x] `secret` (dae5b22)
    - [x] `file`, `directory` and `app` (dae5b22)
    - [x] `button` with its result line, and `heading` (dae5b22)
- [x] Settings: options from the plugin
    - [x] Call options providers with a spinner; show errors with Retry (dae5b22)
    - [x] Keep a saved value missing from new options, marked "not found" (dae5b22)
    - [x] Reload a field's options when a field in its `dependsOn` changes (dae5b22)
- [x] Settings: saving
    - [x] Validate and save 0.5 s after the last edit; show inline errors (dae5b22)
    - [x] Refresh `host.preferences` before each dispatch, and reload a loaded plugin when they change (dae5b22)
    - [x] Open the settings page with empty required fields highlighted when an action needs them (dae5b22)
- [x] Settings: Permissions section
    - [x] List run-time grants with Remove buttons (dae5b22)
- [x] Verification
    - [x] Unit test each store: persistence across reload, quotas, per-value limits, eviction order; 1,000 writes and reads in under a second ((KeyValueStoreTests, CacheStoreTests, SecretStoreTests, PreferencesStoreTests, PluginDataManagerTests))
    - [x] UI test with the ODH-shaped plugin and a mock AnkiConnect, including revoking a grant (f98c888)
- [x] Design UML
    - [x] Add as-built UML to the design docs this task built or changed (3f9d1d7)

**Notes for the next agent:** User request 2026-10-11: complete tasks 007 to 013 in order (not 014). Stores use the system SQLite (import SQLite3) and the Keychain; the settings UI is SwiftUI in the app target.
