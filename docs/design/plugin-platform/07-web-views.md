# 07 · Web views

Part of the [Baron Plugin Platform design](README.md).

A web view is a plugin's own HTML page shown by Baron, for UI that generated settings and native views can't express. ODH's dictionary popup is the first. Pages come only from the plugin's package, can't reach the network on their own, and talk to the plugin and to Baron through the same host API.

**Scope.** In: the result panel, settings pages, how pages are served, their security policy, the page bridge, images and audio, lifecycle. Out: native views ([08](08-native-views.md)), the host methods themselves ([03](03-host-api-and-ipc.md)).

## Where pages appear

| Surface | Opened by | Behaviour |
| --- | --- | --- |
| Result panel | `host.ui.openWebView(path, { data })` during a user action | A floating panel next to the selection, placed by the same rules as the action bar (above, else below, kept on screen) |
| Settings page | `settingsPage` in the manifest | Shown under the generated preferences in the plugin's settings ([06](06-settings.md)) |

The result panel:

- **Size:** 420 × 320 points by default; a page may ask for its content height through `baron.view.resize(height)`, up to 640 points, after which it scrolls.
- **Focus:** it takes clicks and scrolling without taking focus from the source app, so the selection stays. A click into a form field gives it keyboard focus until the panel closes.
- **Chrome:** Baron draws a thin header with the plugin's icon and name, a pin button and a close button, so users always know whose page they see.
- **Closing:** a click outside, Escape, switching apps, or a new selection closes it, unless pinned. One result panel shows at a time.

## Serving pages

- **A custom scheme.** Pages load from `baron-plugin://<plugin id>/<path>`, served from the installed package by a `WKURLSchemeHandler`. Paths can't leave the package; MIME types come from the file extension.
- **One data store per plugin.** Each plugin's pages use a non-persistent `WKWebsiteDataStore`: no cookies or storage survive, and plugins can't see each other's. Persistent data goes through `baron.storage`.
- **No navigation away.** Navigating to another origin is blocked. Links open in the user's browser through `baron.ui.openUrl`, and `window.open` is refused.

## Security policy

Every page is served with this Content Security Policy:

```text
default-src 'none';
script-src 'self' [+ 'unsafe-eval' blob: only with code.dynamic];
style-src 'self' 'unsafe-inline';
img-src 'self' data: blob: <hosts from the plugin's network permissions>;
media-src 'self' blob: <hosts from the plugin's network permissions>;
font-src 'self' data:;
connect-src 'none';
frame-src 'none'; form-action 'none'; base-uri 'none';
```

Images and audio may load from hosts the plugin may already `fetch` from, because dictionary HTML embeds pictures and pronunciation files. Scripts load only from the package, and inline event handlers never run. Data requests go through `baron.http.fetch`, so the same allowlist and prompts apply ([04](04-permissions-and-security.md)).

## The page bridge

Baron injects one script before the page's own, defining `window.baron`:

| Member | Purpose |
| --- | --- |
| `baron.http`, `baron.storage`, `baron.cache`, `baron.secrets`, `baron.text`, `baron.permissions`, `baron.ui.toast`, `baron.ui.openUrl`, `baron.environment`, `baron.preferences`, `baron.log` | The same host API as in the engine context ([03](03-host-api-and-ipc.md)), with the same permissions |
| `baron.view.data` | The `data` passed to `openWebView` |
| `baron.view.postMessage(message)`, `baron.view.onMessage(listener)` | Messages to and from the plugin's engine context, through its `ViewHandle` |
| `baron.view.resize(height)`, `baron.view.close()` | Panel control |

The bridge uses `WKScriptMessageHandlerWithReply` and the envelopes from [03](03-host-api-and-ipc.md). Baron takes the plugin's identity from the page's origin, never from the message.

## Look and feel

- **Colours:** pages get CSS variables for Baron's colours (`--baron-background`, `--baron-text`, `--baron-accent` and a few more), and `prefers-color-scheme` follows the system.
- **Language:** `baron.environment.locale` gives the user's language.
- **Audio:** plays without an extra click (`mediaTypesRequiringUserActionForPlayback` is empty), because pronunciation buttons are the point.

## Lifecycle and speed

- **One web view per open panel**, released on close.
- **Kept warm:** after closing, the web view stays loaded for 30 s, so the next lookup in a row skips page load.
- **Target:** under 150 ms from click to first paint when warm, under 400 ms when cold.

## Cross-platform

The page bridge and policy are the contract; WebView2 on Windows and WebKitGTK on Linux implement the same scheme, policy and `window.baron`.

## Gate (task-010)

- [ ] A sample plugin opens a result panel next to the selection, sized to its content
- [ ] The page shows an image and plays audio from a declared host; a `fetch` or image from an undeclared host is blocked
- [ ] `baron.*` calls from the page obey the plugin's permissions; messages flow both ways between page and engine context
- [ ] Links open in the browser; the panel closes on an outside click, Escape and app switch, stays open when pinned, and follows dark mode
