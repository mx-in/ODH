import AppKit
import BaronCore
import SwiftUI

/// Shown before a plugin is installed or gains permissions (task-008): who made it, where it comes from, and what it
/// may do, in plain words. Design: 04-permissions-and-security.md#install-and-update-consent
struct InstallSheetView: View {
    let name: String
    let manifest: PluginManifest
    let source: String
    var onInstall: () -> Void = {}
    var onCancel: () -> Void = {}

    private var summary: PermissionWording.Summary { PermissionWording.summary(of: manifest) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "puzzlepiece.extension").font(.system(size: 34)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install “\(name)”?").font(.headline)
                    Text("Version \(manifest.version)\(manifest.author.map { " · \($0)" } ?? "")").foregroundStyle(.secondary)
                    Text("From \(source) · Unsigned").font(.caption).foregroundStyle(.secondary)
                }
            }
            if summary.isEmpty {
                Text("This plugin asks for no permissions. It only sees the text you choose to run it on.").foregroundStyle(.secondary)
            } else {
                group("Reads", summary.reads, "eye")
                group("Connects to", summary.connectsTo, "network")
                group("Can", summary.can, "pencil")
                group("Stores", summary.stores, "key")
                ForEach(summary.disclosures, id: \.self) { text in
                    Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Install", action: onInstall).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .accessibilityIdentifier("baron.installSheet")
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [String], _ symbol: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                ForEach(items, id: \.self) { item in
                    Text("• \(item)").padding(.leading, 22).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// `--preview-install-sheet <plugin folder>`: opens the sheet for a plugin, to check its wording before task-008 uses it.
@MainActor
enum InstallSheetPreview {
    static var window: NSWindow?

    static func showIfAsked() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--preview-install-sheet"), flag + 1 < arguments.count else { return }
        let folder = URL(fileURLWithPath: arguments[flag + 1])
        guard let manifest = ManifestValidator().validate(package: folder).manifest else { return }
        let name = PluginLocalizer(package: folder, defaultLocale: manifest.defaultLocale).resolve(manifest.name)
        let view = InstallSheetView(name: name, manifest: manifest, source: "a folder (\(folder.lastPathComponent))",
                                    onInstall: { Self.window?.close() }, onCancel: { Self.window?.close() })
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet.title = "Install Plugin"
        sheet.styleMask = [.titled, .closable]
        sheet.isReleasedWhenClosed = false
        window = sheet
        NSApp.activate(ignoringOtherApps: true)
        sheet.center()
        sheet.makeKeyAndOrderFront(nil)
    }
}
