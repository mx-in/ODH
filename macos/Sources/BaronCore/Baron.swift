/// Product-wide constants shared by the app, the probe and the tests.
public enum Baron {
    public static let name = "Baron"
    public static let bundleIdentifier = "org.odh.baron"
    /// The app's version, compared with a plugin's `minBaronVersion`.
    public static let version = "0.1.0"
    /// Plugin API generations Baron runs: the current one and the one before it.
    public static let apiVersions = 1...1
}
