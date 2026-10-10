import { expect, test } from "bun:test";
import { apiVersion } from "../src/index.ts";

test("targets apiVersion 1", () => {
    expect(apiVersion).toBe(1);
});
