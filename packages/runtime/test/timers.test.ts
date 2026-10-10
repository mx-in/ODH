import { describe, expect, test } from "bun:test";
import { Channel } from "../src/channel.ts";
import { createConsole } from "../src/console.ts";
import { Timers } from "../src/timers.ts";

function setup() {
    const armed: Array<[number, number]> = [];
    const cleared: number[] = [];
    const errors: unknown[] = [];
    const native = { send() {}, setTimer: (id: number, ms: number) => armed.push([id, ms]), clearTimer: (id: number) => cleared.push(id), randomBytes: () => [] };
    const timers = new Timers(native, (e) => errors.push(e));
    const globals: Record<string, any> = {};
    timers.install(globals);
    return { timers, globals, armed, cleared, errors };
}

describe("timers", () => {
    test("setTimeout arms a native timer and runs once with its arguments", () => {
        const { timers, globals, armed } = setup();
        const calls: unknown[] = [];
        const id = globals.setTimeout((a: number, b: number) => calls.push(a + b), 25, 2, 3);
        expect(armed).toEqual([[id, 25]]);
        timers.fire(id);
        timers.fire(id);
        expect(calls).toEqual([5]);
        expect(timers.activeCount).toBe(0);
    });

    test("setInterval re-arms after each run until cleared", () => {
        const { timers, globals, armed, cleared } = setup();
        let runs = 0;
        const id = globals.setInterval(() => runs++, 10);
        timers.fire(id);
        timers.fire(id);
        expect(armed).toEqual([[id, 10], [id, 10], [id, 10]]);
        globals.clearInterval(id);
        timers.fire(id);
        expect(runs).toBe(2);
        expect(cleared).toEqual([id]);
    });

    test("bad delays become zero and callbacks must be functions", () => {
        const { globals, armed } = setup();
        globals.setTimeout(() => {}, -5);
        globals.setTimeout(() => {}, "soon");
        expect(armed.map(([, ms]) => ms)).toEqual([0, 0]);
        expect(() => globals.setTimeout("alert(1)", 0)).toThrow(TypeError);
    });

    test("a throwing callback is reported and doesn't stop other timers", () => {
        const { timers, globals, errors } = setup();
        const a = globals.setTimeout(() => { throw new Error("boom"); }, 0);
        let ran = false;
        const b = globals.setTimeout(() => (ran = true), 0);
        timers.fire(a);
        timers.fire(b);
        expect((errors[0] as Error).message).toBe("boom");
        expect(ran).toBe(true);
    });

    test("queueMicrotask runs before the next task and reports errors", async () => {
        const { globals, errors } = setup();
        const order: string[] = [];
        globals.queueMicrotask(() => order.push("micro"));
        globals.queueMicrotask(() => { throw new Error("late"); });
        order.push("sync");
        await Promise.resolve();
        await Promise.resolve();
        expect(order).toEqual(["sync", "micro"]);
        expect((errors[0] as Error).message).toBe("late");
    });
});

describe("console", () => {
    test("sends each line to log at its level", () => {
        const sent: any[] = [];
        const channel = new Channel({ send: (json) => sent.push(JSON.parse(json)), setTimer() {}, clearTimer() {}, randomBytes: () => [] });
        const console = createConsole(channel);
        console.log("a", 1);
        console.warn({ b: 2 });
        console.count();
        console.count();
        console.assert(false, "x");
        expect(sent.map((e) => [e.method, e.args[0]])).toEqual([["info", "a 1"], ["warn", '{"b":2}'], ["info", "default: 1"], ["info", "default: 2"], ["error", "Assertion failed x"]]);
    });
});
