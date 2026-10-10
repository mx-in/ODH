import AppKit
import BaronCore
import SwiftUI
import UniformTypeIdentifiers

/// One preference's control, its description, and its error. Design: 06-settings.md#preference-types
struct PreferenceRow: View {
    let preference: Preference
    @ObservedObject var page: PluginPage
    let highlighted: Bool

    private var title: String { page.text(preference.title) }
    private var value: JSONValue? { page.values[preference.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
            if let description = preference.description { Text(page.text(description)).font(.caption).foregroundStyle(.secondary) }
            if let error = page.errors[preference.id] {
                Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("pref.\(preference.id).error")
            }
        }
        .padding(highlighted ? 6 : 0)
        .background(highlighted ? Color.yellow.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var control: some View {
        switch preference.type {
        case .heading:
            Text(title).font(.headline).padding(.top, 6)
        case .text:
            LabeledContent(title) {
                if preference.multiline == true {
                    TextEditor(text: string).frame(minHeight: 60).accessibilityIdentifier("pref.\(preference.id)")
                } else {
                    TextField(page.text(preference.placeholder), text: string).accessibilityIdentifier("pref.\(preference.id)")
                }
            }
        case .number:
            LabeledContent(title) {
                HStack {
                    TextField("", value: number, format: .number).frame(width: 80).accessibilityIdentifier("pref.\(preference.id)")
                    Stepper("", value: number, in: (preference.min ?? -.greatestFiniteMagnitude)...(preference.max ?? .greatestFiniteMagnitude), step: preference.step ?? 1).labelsHidden()
                }
            }
        case .checkbox:
            Toggle(preference.label.map(page.text) ?? title, isOn: bool).accessibilityIdentifier("pref.\(preference.id)")
        case .dropdown:
            DropdownControl(preference: preference, page: page, title: title)
        case .checklist:
            ChecklistControl(preference: preference, page: page, title: title)
        case .list:
            ListControl(preference: preference, page: page, title: title)
        case .secret:
            SecretControl(preference: preference, page: page, title: title)
        case .file, .directory:
            LabeledContent(title) {
                HStack {
                    Text(value?.stringValue.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { choosePath() }.accessibilityIdentifier("pref.\(preference.id)")
                }
            }
        case .app:
            LabeledContent(title) {
                HStack {
                    Text(value?.stringValue.map(appName) ?? "None").foregroundStyle(.secondary)
                    Button("Choose…") { chooseApp() }.accessibilityIdentifier("pref.\(preference.id)")
                }
            }
        case .button:
            HStack {
                if !title.isEmpty { Text(title) }
                Button(page.text(preference.label)) { Task { await page.press(preference) } }.accessibilityIdentifier("pref.\(preference.id)")
                if let result = page.buttonResults[preference.id] {
                    Text(result.message).font(.caption).foregroundStyle(result.isError ? .red : .secondary).accessibilityIdentifier("pref.\(preference.id).result")
                }
            }
        }
    }

    private var string: Binding<String> {
        Binding { value?.stringValue ?? "" } set: { page.set(preference, to: .string($0)) }
    }

    private var number: Binding<Double> {
        Binding { if case .number(let n)? = value { n } else { preference.min ?? 0 } } set: { page.set(preference, to: .number($0)) }
    }

    private var bool: Binding<Bool> {
        Binding { if case .bool(let b)? = value { b } else { false } } set: { page.set(preference, to: .bool($0)) }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = preference.type == .directory
        panel.canChooseFiles = preference.type == .file
        if let extensions = preference.extensions { panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) } }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        page.set(preference, to: .string(url.path))
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        page.set(preference, to: .string(id))
    }

    private func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    }
}

/// A pop-up menu; options may come from the plugin. A saved value the options no longer include stays, marked
/// "not found", so a closed Anki doesn't erase settings.
struct DropdownControl: View {
    let preference: Preference
    @ObservedObject var page: PluginPage
    let title: String

    var body: some View {
        LabeledContent(title) {
            switch (page.choices(preference), page.options[preference.id]) {
            case (let choices?, _):
                Picker("", selection: Binding { page.values[preference.id]?.stringValue ?? "" } set: { page.set(preference, to: .string($0)) }) {
                    if page.values[preference.id]?.stringValue == nil { Text("Choose…").tag("") }
                    ForEach(choices, id: \.value) { option in Text(option.title).tag(option.value) }
                    if let saved = page.values[preference.id]?.stringValue, !saved.isEmpty, !choices.contains(where: { $0.value == saved }) {
                        Text("\(saved) (not found)").tag(saved)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("pref.\(preference.id)")
            case (nil, .failed(let message)?):
                HStack {
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(2).accessibilityIdentifier("pref.\(preference.id).error")
                    Button("Retry") { Task { await page.loadOptions(preference) } }.accessibilityIdentifier("pref.\(preference.id).retry")
                }
            default:
                ProgressView().controlSize(.small).accessibilityIdentifier("pref.\(preference.id).loading")
            }
        }
    }
}

/// A list of checkboxes; the value keeps the options' order.
struct ChecklistControl: View {
    let preference: Preference
    @ObservedObject var page: PluginPage
    let title: String

    private var selected: [String] {
        if case .array(let items)? = page.values[preference.id] { return items.compactMap(\.stringValue) }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let choices = page.choices(preference) {
                ForEach(choices, id: \.value) { option in
                    Toggle(option.title, isOn: Binding {
                        selected.contains(option.value)
                    } set: { on in
                        let next = choices.map(\.value).filter { $0 == option.value ? on : selected.contains($0) }
                        page.set(preference, to: .array(next.map(JSONValue.string)))
                    })
                    .accessibilityIdentifier("pref.\(preference.id).\(option.value)")
                }
            } else if case .failed(let message)? = page.options[preference.id] {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Retry") { Task { await page.loadOptions(preference) } }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// An editable list of text items with add, remove and reorder.
struct ListControl: View {
    let preference: Preference
    @ObservedObject var page: PluginPage
    let title: String
    @State private var draft = ""

    private var items: [String] {
        if case .array(let values)? = page.values[preference.id] { return values.compactMap(\.stringValue) }
        return []
    }

    private func update(_ next: [String]) {
        page.set(preference, to: .array(next.map(JSONValue.string)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Button { var next = items; next.swapAt(index, index - 1); update(next) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0).buttonStyle(.borderless)
                    Button { var next = items; next.swapAt(index, index + 1); update(next) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == items.count - 1).buttonStyle(.borderless)
                    Button { var next = items; next.remove(at: index); update(next) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).accessibilityIdentifier("pref.\(preference.id).remove.\(index)")
                }
            }
            HStack {
                TextField(page.text(preference.itemPlaceholder), text: $draft).accessibilityIdentifier("pref.\(preference.id).new")
                Button("Add") {
                    let item = draft.trimmingCharacters(in: .whitespaces)
                    guard !item.isEmpty else { return }
                    update(items + [item])
                    draft = ""
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("pref.\(preference.id).add")
            }
        }
    }
}

/// A secure field saved straight to the Keychain; the value is never shown again.
struct SecretControl: View {
    let preference: Preference
    @ObservedObject var page: PluginPage
    let title: String
    @State private var draft = ""

    var body: some View {
        LabeledContent(title) {
            HStack {
                SecureField(page.secretSaved[preference.id] == true ? "Saved in the Keychain" : page.text(preference.placeholder), text: $draft)
                    .accessibilityIdentifier("pref.\(preference.id)")
                Button("Save") { page.saveSecret(preference, draft); draft = "" }.disabled(draft.isEmpty)
                    .accessibilityIdentifier("pref.\(preference.id).save")
                if page.secretSaved[preference.id] == true {
                    Button("Remove") { page.saveSecret(preference, "") }.accessibilityIdentifier("pref.\(preference.id).remove")
                }
            }
        }
    }
}
