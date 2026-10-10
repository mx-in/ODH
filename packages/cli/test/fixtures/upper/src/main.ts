import { definePlugin } from "@baron/api";
import { shout } from "./shout.ts";

export default definePlugin({
    actions: {
        upper: (context) => ({ type: "replace", text: shout(context.text) }),
    },
});
