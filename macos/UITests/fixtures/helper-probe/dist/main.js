// Prebuilt on purpose: the UI test needs no Bun. onInstall waits a little, so the test can stop the helper
// meanwhile, then says where it ran.
globalThis.__baronPlugin = {
    actions: { probe: () => undefined },
    lifecycle: {
        async onInstall(host) {
            await new Promise((resolve) => setTimeout(resolve, 3000));
            await host.ui.toast("helper probe: installed");
        },
    },
};
