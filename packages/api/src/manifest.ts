/**
 * The plugin manifest, `manifest.json` at the root of a plugin package.
 * Baron reads all of it without running plugin code. Design: docs/design/plugin-platform/01-package-and-manifest.md
 */

/** Text shown to users: either the text itself, or `%key%`, looked up in `locales/<language>.json`. */
export type LocalizedString = string;

export type Platform = "macos" | "windows" | "linux";

/** Permissions that aren't network patterns. Design: 04-permissions-and-security.md */
export type FixedPermission =
    | "context.sentence"
    | "context.paragraph"
    | "context.page"
    | "context.window"
    | "clipboard.read"
    | "selection.replace"
    | "secrets"
    | "code.dynamic";

/**
 * `network:` followed by a host pattern: `dict.cn`, `*.youdao.com`, `api.example.com:8443`,
 * `http://example.com` (plain HTTP must be written out) or `127.0.0.1:8765`.
 */
export type NetworkPermission = `network:${string}`;

export type Permission = FixedPermission | NetworkPermission;

/** `network:*` is only allowed here: Baron then asks the user for each new host. */
export type OptionalPermission = Permission | "network:*";

/** Context an action reads besides the text. Each needs the matching `context.*` permission. */
export type ContextField = "sentence" | "paragraph" | "page" | "window";

/** `word` is one word of letters; `text` matches anything. */
export type ContentType = "word" | "url" | "email" | "number" | "text";

/** A bundle ID on macOS, or one ID per platform. */
export type AppMatch = string | { macos?: string; windows?: string; linux?: string };

/** Rules Baron checks before showing an action. All must hold; a missing rule doesn't constrain. */
export interface WhenRules {
    /** Length of the trimmed text in UTF-16 code units. */
    minLength?: number;
    maxLength?: number;
    /** ECMAScript syntax, compiled with the `u` flag; it must also compile as an ICU pattern. */
    regex?: string;
    contentTypes?: ContentType[];
    apps?: AppMatch[];
    excludeApps?: AppMatch[];
    /** Whether the selection can be replaced. */
    editable?: boolean;
}

export interface ManifestAction {
    /** Unique within the plugin, and the exported handler's name unless `run` says otherwise. */
    id: string;
    run?: string;
    title: LocalizedString;
    /** An SVG file in the package; the plugin icon if missing. */
    icon?: string;
    when?: WhenRules;
    needs?: ContextField[];
    /** `allowed` lets the user run this action straight after a selection. Only for actions without side effects. */
    autoRun?: "allowed" | "never";
}

export interface PreferenceOption {
    value: string;
    title: LocalizedString;
    subtitle?: LocalizedString;
}

export type PreferenceValue = string | number | boolean | string[];

interface PreferenceBase {
    /** Unique within the plugin; the key in `host.preferences`. */
    id: string;
    title: LocalizedString;
    description?: LocalizedString;
    /** Actions don't run until a required preference has a value. */
    required?: boolean;
}

/** Fixed options, or options returned by the plugin's `options[optionsFrom]` provider. */
type OptionsSource =
    | { options: PreferenceOption[]; optionsFrom?: never }
    | { optionsFrom: string; options?: never };

export interface TextPreference extends PreferenceBase {
    type: "text";
    default?: string;
    placeholder?: LocalizedString;
    multiline?: boolean;
    /** ECMAScript syntax, searched for like `RegExp.test`; anchor with `^` and `$` to match the whole value. */
    pattern?: string;
    maxLength?: number;
}

export interface NumberPreference extends PreferenceBase {
    type: "number";
    default?: number;
    min?: number;
    max?: number;
    step?: number;
}

export interface CheckboxPreference extends PreferenceBase {
    type: "checkbox";
    default?: boolean;
    label?: LocalizedString;
}

export type DropdownPreference = PreferenceBase & OptionsSource & {
    type: "dropdown";
    default?: string;
    /** Preference IDs whose change reloads this field's options. */
    dependsOn?: string[];
};

export type ChecklistPreference = PreferenceBase & OptionsSource & {
    type: "checklist";
    default?: string[];
    dependsOn?: string[];
};

export interface ListPreference extends PreferenceBase {
    type: "list";
    default?: string[];
    itemPlaceholder?: LocalizedString;
    /** ECMAScript syntax, searched for in every item like `RegExp.test`; anchor with `^` and `$` for whole items. */
    itemPattern?: string;
    maxItems?: number;
}

/** Stored in the Keychain; read with `host.secrets.get(id)`, never in `host.preferences`. */
export interface SecretPreference extends PreferenceBase {
    type: "secret";
    placeholder?: LocalizedString;
}

export interface FilePreference extends PreferenceBase {
    type: "file";
    /** File name extensions without the dot, such as `json`. */
    extensions?: string[];
}

export interface DirectoryPreference extends PreferenceBase {
    type: "directory";
}

/** An app picker; the value is a bundle ID on macOS. */
export interface AppPreference extends PreferenceBase {
    type: "app";
    default?: string;
}

/** A push button that calls the plugin's `buttons[run]` and shows the returned message. */
export interface ButtonPreference extends Omit<PreferenceBase, "required"> {
    type: "button";
    run: string;
    label: LocalizedString;
}

export interface HeadingPreference extends Omit<PreferenceBase, "required"> {
    type: "heading";
}

export type Preference =
    | TextPreference
    | NumberPreference
    | CheckboxPreference
    | DropdownPreference
    | ChecklistPreference
    | ListPreference
    | SecretPreference
    | FilePreference
    | DirectoryPreference
    | AppPreference
    | ButtonPreference
    | HeadingPreference;

export type PreferenceType = Preference["type"];

export interface PluginManifest {
    $schema?: string;
    /** Reverse-DNS, lowercase, unique, and never changed between versions. */
    id: string;
    name: LocalizedString;
    description: LocalizedString;
    /** Semantic version; a higher version is an update. */
    version: string;
    /** The host API generation the plugin targets. */
    apiVersion: 1;
    author?: string;
    homepage?: string;
    license?: string;
    /** The language used when the user's isn't available. Required when any string is `%key%`. */
    defaultLocale?: string;
    /** The bundled code, relative to the package. */
    main: string;
    /** An SVG file; also the default action icon. */
    icon?: string;
    /** All three when missing. A host refuses a plugin that excludes it. */
    platforms?: Platform[];
    /** Baron refuses to install on older versions. */
    minBaronVersion?: string;
    permissions?: Permission[];
    optionalPermissions?: OptionalPermission[];
    preferences?: Preference[];
    /** A web page shown under the generated settings. */
    settingsPage?: string;
    /** Reserved for a native settings view (after ODH). */
    settingsView?: string;
    actions: [ManifestAction, ...ManifestAction[]];
}
