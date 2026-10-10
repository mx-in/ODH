import { describe, expect, test } from "bun:test";
import { BaronError, errorCodes, isBaronError } from "../src/index.ts";

describe("BaronError", () => {
    test("carries its code, message and data", () => {
        const error = new BaronError("permission_denied", "network:dict.cn is not granted", { permission: "network:dict.cn", requestable: true });
        expect(error).toBeInstanceOf(Error);
        expect(error.name).toBe("BaronError");
        expect(error.code).toBe("permission_denied");
        expect(error.message).toBe("network:dict.cn is not granted");
        expect(error.data).toEqual({ permission: "network:dict.cn", requestable: true });
    });

    test("lists the nine codes from the design", () => {
        expect(errorCodes).toEqual([
            "permission_denied",
            "user_action_required",
            "invalid_argument",
            "network_error",
            "timeout",
            "quota_exceeded",
            "not_found",
            "unavailable",
            "internal",
        ]);
    });
});

describe("isBaronError", () => {
    test("recognises errors by shape, so copies of the class from another bundle still match", () => {
        const fromAnotherBundle = Object.assign(new Error("slow"), { name: "BaronError", code: "timeout" });
        expect(isBaronError(fromAnotherBundle)).toBe(true);
        expect(isBaronError(fromAnotherBundle, "timeout")).toBe(true);
        expect(isBaronError(fromAnotherBundle, "internal")).toBe(false);
    });

    test("rejects other errors and values", () => {
        expect(isBaronError(new Error("plain"))).toBe(false);
        expect(isBaronError(Object.assign(new Error("x"), { name: "BaronError", code: "made_up" }))).toBe(false);
        expect(isBaronError(null)).toBe(false);
        expect(isBaronError("timeout")).toBe(false);
    });
});
