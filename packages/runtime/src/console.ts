import type { Channel } from "./channel.ts";
import { formatValue } from "./format.ts";

/** A console whose lines go to `host.log`: private in the system log, shown in full under `baron dev`. */
export function createConsole(channel: Channel): Console {
    const line = (level: string) => (...values: unknown[]) => channel.notify("log", level, [values.map(formatValue).join(" ")]);
    const counts = new Map<string, number>();
    const timers = new Map<string, number>();
    const console = {
        log: line("info"), info: line("info"), debug: line("debug"), warn: line("warn"), error: line("error"),
        trace: (...values: unknown[]) => line("debug")(...values, new Error("trace").stack ?? ""),
        assert: (condition: unknown, ...values: unknown[]) => { if (!condition) line("error")("Assertion failed", ...values); },
        count: (label = "default") => { counts.set(label, (counts.get(label) ?? 0) + 1); line("info")(`${label}: ${counts.get(label)}`); },
        countReset: (label = "default") => void counts.delete(label),
        time: (label = "default") => void timers.set(label, Date.now()),
        timeEnd: (label = "default") => { const start = timers.get(label); timers.delete(label); if (start !== undefined) line("info")(`${label}: ${Date.now() - start}ms`); },
        timeLog: (label = "default", ...values: unknown[]) => { const start = timers.get(label); if (start !== undefined) line("info")(`${label}: ${Date.now() - start}ms`, ...values); },
        dir: (value: unknown) => line("info")(value),
        table: (value: unknown) => line("info")(value),
        group: line("info"), groupCollapsed: line("info"), groupEnd: () => {},
    };
    return console as unknown as Console;
}
