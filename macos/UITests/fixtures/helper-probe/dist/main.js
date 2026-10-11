// Prebuilt on purpose: the UI test needs no Bun. onInstall waits a little, so the test can stop the helper
// meanwhile, then says where it ran. The action answers only "zebrafish", so it stays off other selections.
globalThis.__baronPlugin = {
    actions: { probe: () => ({ type: "toast", message: "helper probe: ran" }) },
    lifecycle: {
        async onInstall(host) {
            await new Promise((resolve) => setTimeout(resolve, 3000));
            await host.ui.toast("helper probe: installed");
        },
    },
};
