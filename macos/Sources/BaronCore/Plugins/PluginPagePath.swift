import Foundation

/// Where a page path from `host.ui.openWebView` or a `baron-plugin://` request lives in the plugin's package, and
/// what it is served as. Paths can't leave the package. Design: docs/design/plugin-platform/07-web-views.md
public enum PluginPagePath {
    /// The file for `path` inside `package`; nil when the path is absolute, has a scheme, climbs out with `..`
    /// or through a symbolic link, or the file doesn't exist.
    public static func resolve(_ path: String, in package: URL) -> URL? {
        let trimmed = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.contains("://"), !trimmed.contains("\\"),
              !trimmed.split(separator: "/").contains("..") else { return nil }
        let root = package.standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appendingPathComponent(trimmed).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        return file
    }

    /// The Content-Type for a file, from its extension.
    public static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "html", "htm": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json", "map": "application/json; charset=utf-8"
        case "txt": "text/plain; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "ico": "image/x-icon"
        case "mp3": "audio/mpeg"
        case "m4a": "audio/mp4"
        case "wav": "audio/wav"
        case "ogg", "oga": "audio/ogg"
        case "mp4": "video/mp4"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        case "ttf": "font/ttf"
        case "otf": "font/otf"
        default: "application/octet-stream"
        }
    }
}
