import { definePlugin } from "@baron/api";

/** context.text is a JSON call: { ns, method, args }. Answers { ok, value } or { ok: false, code }. */
export default definePlugin({
    actions: {
        async call(context, host) {
            const { ns, method, args } = JSON.parse(context.text) as { ns: string; method: string; args: unknown[] };
            const namespace = (host as unknown as Record<string, Record<string, (...a: unknown[]) => Promise<unknown>> | undefined>)[ns];
            try {
                const fn = namespace?.[method];
                if (!fn) return { type: "copy", text: JSON.stringify({ ok: false, code: "not_in_host_object" }) };
                const value = await fn(...args);
                return { type: "copy", text: JSON.stringify({ ok: true, value: value ?? null }) };
            } catch (error) {
                const code = (error as { code?: string } | null)?.code ?? "plugin_error";
                return { type: "copy", text: JSON.stringify({ ok: false, code }) };
            }
        },
    },
});
