import { expect, test } from "bun:test";
import type { Host, HttpResponse } from "../src/index.ts";

// These checks run in `tsc`; the runtime test only keeps bun from skipping the file.

async function usesEveryNamespace(host: Host): Promise<string> {
    const text: HttpResponse<string> = await host.http.fetch("https://dict.example/fox");
    const bytes: HttpResponse<Uint8Array> = await host.http.fetch("https://dict.example/fox.mp3", { responseType: "bytes" });
    const history = (await host.storage.get<string[]>("history")) ?? [];
    await host.storage.set("history", [...history, "fox"]);
    await host.cache.set("fox", text.body);
    const key = await host.secrets.get("apiKey");
    const sentences = await host.text.segment("The fox runs. It is quick.", "sentence");
    const view = await host.ui.openWebView("views/popup.html", { data: { word: "fox" } });
    view.onMessage((message) => host.log.info("from page", message));
    await host.permissions.request(["network:dict.cn"]);
    const deck = host.preferences["deck"];
    return [host.environment.locale, bytes.body.length, key, sentences.length, deck].join();
}

// @ts-expect-error the environment is read-only
const writesEnvironment = (host: Host) => { host.environment.locale = "en"; };

// @ts-expect-error a response body is text unless bytes are asked for
const textAsBytes = async (host: Host) => { const r: HttpResponse<Uint8Array> = await host.http.fetch("https://x.example"); return r; };

test("host types accept the documented calls", () => {
    expect([usesEveryNamespace, writesEnvironment, textAsBytes]).toHaveLength(3);
});
