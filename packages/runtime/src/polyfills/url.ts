// core-js's WHATWG URL, installed unconditionally so every engine parses URLs the same way.
import URL from "core-js-pure/actual/url/index.js";
import URLSearchParams from "core-js-pure/actual/url-search-params/index.js";

export { URL, URLSearchParams };

export function installURL(target: Record<string, unknown>): void {
    target["URL"] = URL;
    target["URLSearchParams"] = URLSearchParams;
}
