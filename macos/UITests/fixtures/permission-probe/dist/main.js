// Prebuilt on purpose: the UI test needs no Bun. Asks for one host and reports the answer.
globalThis.__baronPlugin = {
    actions: {
        async probe(context, host) {
            const granted = await host.permissions.request(["network:probe.example"]);
            return { type: "toast", message: granted.length ? "probe: granted" : "probe: denied" };
        },
    },
};
