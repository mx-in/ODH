/**
 * What a plugin's bundle exports. `baron build` assigns the default export to `globalThis.__baronPlugin`,
 * and the prelude calls into it. Design: docs/design/plugin-platform/02-runtime.md#plugin-code-format
 */
import type { ActionResult, SelectionContext, ToastKind } from "./context.ts";
import type { Host, Preferences } from "./host.ts";
import type { PreferenceOption } from "./manifest.ts";

/** Runs when the user picks the action; 10 s limit. */
export type ActionHandler = (context: SelectionContext, host: Host) => ActionResult | Promise<ActionResult>;

/** Fills a `dropdown` or `checklist` whose `optionsFrom` names it; 5 s limit. */
export type OptionsProvider = (preferences: Preferences, host: Host) => PreferenceOption[] | Promise<PreferenceOption[]>;

/** The line shown next to a settings button. */
export type ButtonResult = { message: string; kind?: ToastKind } | void;

/** Runs when a `button` preference whose `run` names it is clicked; 10 s limit. */
export type ButtonHandler = (preferences: Preferences, host: Host) => ButtonResult | Promise<ButtonResult>;

export interface PluginLifecycle {
    /** Once after install; 10 s limit. A failure is shown but doesn't undo the install. */
    onInstall?(host: Host): void | Promise<void>;
    /** Once before the first dispatch of a new version; migrate storage here. */
    onUpdate?(update: { previousVersion: string }, host: Host): void | Promise<void>;
}

export interface PluginDefinition {
    /** Keyed by each manifest action's `run`, or its `id` when `run` is missing. */
    actions: Record<string, ActionHandler>;
    options?: Record<string, OptionsProvider>;
    buttons?: Record<string, ButtonHandler>;
    lifecycle?: PluginLifecycle;
}

/** Declares a plugin's handlers. It returns its argument unchanged; it exists for type checking. */
export function definePlugin<const Definition extends PluginDefinition>(definition: Definition): Definition {
    return definition;
}
