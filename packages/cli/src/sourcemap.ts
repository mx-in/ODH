/** Maps positions in a bundle back to its TypeScript sources through the bundle's inline source map. */

interface Segment { column: number; source: number; line: number; sourceColumn: number }

const base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function decodeVLQ(text: string): number[] {
    const values: number[] = [];
    let value = 0, shift = 0;
    for (const char of text) {
        const digit = base64.indexOf(char);
        value += (digit & 31) << shift;
        if (digit & 32) {
            shift += 5;
        } else {
            values.push(value & 1 ? -(value >>> 1) : value >>> 1);
            value = 0;
            shift = 0;
        }
    }
    return values;
}

export class SourceMap {
    private readonly lines: Segment[][] = [];
    readonly sources: string[];

    constructor(map: { sources: string[]; mappings: string }) {
        this.sources = map.sources;
        let source = 0, line = 0, sourceColumn = 0;
        for (const text of map.mappings.split(";")) {
            const segments: Segment[] = [];
            let column = 0;
            for (const part of text.split(",")) {
                if (!part) continue;
                const v = decodeVLQ(part);
                column += v[0]!;
                if (v.length >= 4) {
                    source += v[1]!;
                    line += v[2]!;
                    sourceColumn += v[3]!;
                    segments.push({ column, source, line, sourceColumn });
                }
            }
            this.lines.push(segments);
        }
    }

    /** From the bundle's inline `//# sourceMappingURL=data:…` comment. */
    static fromBundle(code: string): SourceMap | undefined {
        const match = code.match(/\/\/# sourceMappingURL=data:application\/json;base64,([A-Za-z0-9+/=]+)/);
        return match ? new SourceMap(JSON.parse(Buffer.from(match[1]!, "base64").toString())) : undefined;
    }

    /** 1-based line and column in the bundle → 1-based position in the source. */
    lookup(line: number, column: number): { source: string; line: number; column: number } | undefined {
        const segments = this.lines[line - 1];
        if (!segments?.length) return undefined;
        let best = segments[0]!;
        for (const segment of segments) if (segment.column <= column - 1) best = segment;
        return { source: this.sources[best.source]!, line: best.line + 1, column: best.sourceColumn + 1 };
    }

    /** Rewrites `main.js:LINE:COL` positions in a stack trace to `src/file.ts:LINE:COL`. */
    rewrite(stack: string, bundleName = "main.js"): string {
        const escaped = bundleName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        return stack.replace(new RegExp(`[^\\s@(]*${escaped}:(\\d+):(\\d+)`, "g"), (whole, l: string, c: string) => {
            const found = this.lookup(Number(l), Number(c));
            return found ? `${found.source.replace(/^(\.\.\/)+/, "")}:${found.line}:${found.column}` : whole;
        });
    }
}
