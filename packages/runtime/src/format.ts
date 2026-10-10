/** Turns console and log arguments into text, the way browsers print them, without throwing on cycles. */
export function formatValue(value: unknown): string {
    if (typeof value === "string") return value;
    if (value instanceof Error) return value.stack ? `${value.name}: ${value.message}\n${value.stack}` : `${value.name}: ${value.message}`;
    if (typeof value === "function") return `[Function ${value.name || "anonymous"}]`;
    if (typeof value === "bigint") return `${value}n`;
    if (typeof value === "symbol" || value === undefined) return String(value);
    try {
        const seen = new WeakSet<object>();
        return JSON.stringify(value, (_key, v: unknown) => {
            if (typeof v === "bigint") return `${v}n`;
            if (v instanceof Uint8Array) return `Uint8Array(${v.length})`;
            if (v !== null && typeof v === "object") {
                if (seen.has(v)) return "[Circular]";
                seen.add(v);
            }
            return v;
        }) ?? String(value);
    } catch {
        return String(value);
    }
}
