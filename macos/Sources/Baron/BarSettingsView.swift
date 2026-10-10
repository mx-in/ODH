import BaronCore
import BaronPlatform
import KeyboardShortcuts
import SwiftUI

/// The bar's actions, built-in and from plugins, as Settings lists them.
struct BarActionInfo: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var mayAutoRun: Bool

    static let builtIns = [
        BarActionInfo(id: "builtin.copy", title: "Copy", subtitle: "Built in", mayAutoRun: false),
        BarActionInfo(id: "builtin.search", title: "Search", subtitle: "Built in", mayAutoRun: false),
        BarActionInfo(id: "builtin.openLink", title: "Open Link", subtitle: "Built in", mayAutoRun: false),
    ]

    static func all(_ catalog: PluginActionCatalog) -> [BarActionInfo] {
        builtIns + catalog.entries.map { BarActionInfo(id: $0.itemID, title: $0.title, subtitle: $0.pluginName, mayAutoRun: $0.mayAutoRun) }
    }
}

extension KeyboardShortcuts.Name {
    /// An action's own hotkey.
    static func action(_ id: String) -> Self { Self("action.\(id)") }
}

/// Settings › Bar: order, show or hide, Run on selection and hotkeys. Design: 10-install-and-lifecycle.md#actions-on-the-bar
struct BarSettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    let catalog: () -> PluginActionCatalog

    private var actions: [BarActionInfo] {
        let all = BarActionInfo.all(catalog())
        let shown = store.settings.bar.arrange(all.map { BarItem(id: $0.id, title: $0.title, symbolName: nil) }).map(\.id)
        let order = shown + all.map(\.id).filter { !shown.contains($0) }
        return order.compactMap { id in all.first { $0.id == id } }
    }

    var body: some View {
        let list = actions
        List {
            Section {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, action in
                    row(action, index: index, count: list.count, all: list.map(\.id))
                }
                .onMove { from, to in
                    var ids = list.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    store.settings.bar.order = ids
                }
            } header: {
                Text("Drag or use the arrows to order the bar. Hidden actions stay installed.")
            }
        }
        .id(navigation.revision)
    }

    @ViewBuilder
    private func row(_ action: BarActionInfo, index: Int, count: Int, all: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text(action.title)
                    Text(action.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.settings.bar.move(action.id, by: -1, among: all) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless).disabled(index == 0).accessibilityIdentifier("bar.\(action.id).up")
                Button { store.settings.bar.move(action.id, by: 1, among: all) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderless).disabled(index == count - 1).accessibilityIdentifier("bar.\(action.id).down")
                Toggle("Show", isOn: Binding {
                    !store.settings.bar.hidden.contains(action.id)
                } set: { show in
                    store.settings.bar.hidden.removeAll { $0 == action.id }
                    if !show { store.settings.bar.hidden.append(action.id) }
                })
                .accessibilityIdentifier("bar.\(action.id).show")
            }
            HStack {
                KeyboardShortcuts.Recorder("Hotkey:", name: .action(action.id))
                if action.mayAutoRun {
                    Toggle("Run on selection", isOn: Binding {
                        store.settings.bar.runOnSelection[action.id] != nil
                    } set: { on in
                        store.settings.bar.runOnSelection[action.id] = on ? [] : nil
                    })
                    .accessibilityIdentifier("bar.\(action.id).autoRun")
                    if let apps = store.settings.bar.runOnSelection[action.id] {
                        TextField("In all apps, or bundle IDs separated by commas", text: Binding {
                            apps.joined(separator: ", ")
                        } set: { text in
                            store.settings.bar.runOnSelection[action.id] = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        })
                        .accessibilityIdentifier("bar.\(action.id).apps")
                    }
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("bar.\(action.id)")
    }
}

/// Registers each action's hotkey once; pressing it runs the action on the current selection.
@MainActor
final class ActionHotkeys {
    private var registered = Set<String>()
    var run: (String) -> Void = { _ in }

    func register(_ actions: [BarActionInfo]) {
        for action in actions where !registered.contains(action.id) {
            registered.insert(action.id)
            let id = action.id
            KeyboardShortcuts.onKeyUp(for: .action(id)) { [weak self] in self?.run(id) }
        }
    }
}
