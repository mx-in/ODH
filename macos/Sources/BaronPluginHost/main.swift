import BaronRuntime
import Foundation

// BaronPluginHost.xpc: runs every plugin's JavaScriptCore context in a sandbox with no file or network access.
// Baron sends the prelude and bundles over the connection, and the plugins' host calls come back to Baron.
// Design: docs/design/plugin-platform/02-runtime.md#stage-2-the-sandboxed-helper

let delegate = PluginHostListener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
