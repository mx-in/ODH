import { definePlugin } from "@baron/api";

export default definePlugin({
    actions: {
        uppercase: (context) => ({ type: "replace", text: context.text.toLocaleUpperCase() }),
    },
});
