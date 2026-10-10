// Prebuilt on purpose: the UI test needs no Bun. Talks to baron-uitest's mock AnkiConnect.
async function anki(prefs, action, params) {
    const response = await fetch(String(prefs.ankiUrl), { method: "POST", body: JSON.stringify({ action, version: 6, params: params || {} }) });
    const answer = await response.json();
    if (answer.error) throw new Error(answer.error);
    return answer.result;
}
const list = (names) => names.map((name) => ({ value: name, title: name }));
globalThis.__baronPlugin = {
    actions: {
        probe: (context, host) => ({ type: "toast", message: "probe ran with deck " + host.preferences.deck }),
    },
    options: {
        decks: async (prefs) => list(await anki(prefs, "deckNames")),
        noteTypes: async (prefs) => list(await anki(prefs, "modelNames")),
        noteFields: async (prefs) => list(await anki(prefs, "modelFieldNames", { modelName: prefs.noteType })),
    },
    buttons: {
        testAnki: async (prefs) => ({ message: "Connected to AnkiConnect " + (await anki(prefs, "version")), kind: "success" }),
    },
};
