// The panel page: window.baron gives the host API and baron.view for this panel.
/** @type {{ word: string, entries: Array<{ entry: string, explain: string }> }} */
const data = baron.view.data;
const statusLine = document.getElementById("status");

document.getElementById("word").textContent = data.word;

// Audio may load from hosts in the plugin's network permissions, and plays without an extra click.
const voice = new Audio(`https://dict.youdao.com/dictvoice?audio=${encodeURIComponent(data.word)}&type=2`);
document.getElementById("say").addEventListener("click", () => {
    voice.play().catch(() => { statusLine.textContent = "The pronunciation can't be played."; });
});

const list = document.getElementById("entries");
for (const { entry, explain } of data.entries) {
    const item = document.createElement("li");
    const word = Object.assign(document.createElement("span"), { className: "entry", textContent: entry });
    const meaning = Object.assign(document.createElement("span"), { className: "explain", textContent: explain });
    const copy = Object.assign(document.createElement("button"), { textContent: "Copy" });
    copy.addEventListener("click", () => baron.view.postMessage({ copy: `${entry}: ${explain}` }));
    item.append(word, meaning, copy);
    list.append(item);
}

baron.view.onMessage((message) => {
    if (message.copied) statusLine.textContent = "Copied.";
});

baron.view.resize(document.body.scrollHeight + 20);
