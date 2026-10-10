/** The contract between Baron and its plugins, apiVersion 1. */
export const apiVersion = 1;

export type * from "./manifest.ts";
export type * from "./context.ts";
export type * from "./host.ts";
export { BaronError, errorCodes, isBaronError } from "./errors.ts";
export type { ErrorCode } from "./errors.ts";
export { definePlugin } from "./plugin.ts";
export type * from "./plugin.ts";
