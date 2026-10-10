/// The text Baron shows when a plugin action fails: it always names the plugin and says what went wrong.
public enum PluginErrorMessage {
    public static func text(for error: HostError, pluginName: String) -> String {
        switch error.code {
        case "timeout": "\(pluginName) took too long to answer."
        case "unavailable": "\(pluginName) isn't available: \(error.message)"
        case "plugin_error": "\(pluginName) failed: \(error.message)"
        case "not_found": "\(pluginName) can't run this action: \(error.message)"
        default: "\(pluginName): \(error.message)"
        }
    }
}
