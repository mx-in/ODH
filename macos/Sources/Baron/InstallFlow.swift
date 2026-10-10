import AppKit
import BaronCore
import BaronPlatform
import BaronRuntime
import SwiftUI

/// Installs plugins from folders, files, links and Baron's bundle, asking with the install sheet when the design says
/// so. Design: 10-install-and-lifecycle.md#installing
@MainActor
final class InstallFlow {
    private let controller: PluginController
    private var sheet: NSWindow?

    init(controller: PluginController) {
        self.controller = controller
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .init(filenameExtension: "baronplugin") ?? .zip]
        panel.message = "Choose a plugin folder or a .baronplugin file."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await install(from: url) }
    }

    /// A folder, a `.baronplugin` file, or a `baron://install?url=https://…` link.
    func install(from url: URL) async {
        do {
            if url.scheme == "baron" {
                let file = try await download(url)
                try await present(PackageReader.read(archive: file, into: scratch(), source: .link(Self.linkTarget(url)?.absoluteString ?? url.absoluteString)))
            } else if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try await present(PackageReader.read(folder: url, source: .folder(url.path)))
            } else {
                try await present(PackageReader.read(archive: url, into: scratch(), source: .file(url.path)))
            }
        } catch {
            fail(error)
        }
    }

    /// First launch: offers each bundled plugin once, with the normal sheet; nothing is enabled silently.
    func offerBundled(settings: SettingsStore) async {
        // Resources/Plugins: Contents/PlugIns is reserved for code bundles, which code signing checks.
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Plugins"),
              let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for entry in entries where FileManager.default.fileExists(atPath: entry.appendingPathComponent("manifest.json").path) {
            guard let package = try? PackageReader.read(folder: entry, source: .bundled),
                  !settings.settings.offeredBundledPlugins.contains(package.manifest.id),
                  await controller.installer.record(package.manifest.id) == nil else { continue }
            settings.settings.offeredBundledPlugins.append(package.manifest.id)
            await present(package)
        }
    }

    private func present(_ package: PluginPackage) async {
        let plan = await controller.installer.plan(package)
        guard plan.needsSheet else {
            await finish(plan, consented: false)
            return
        }
        let name = PluginLocalizer(package: package.folder, defaultLocale: package.manifest.defaultLocale).resolve(package.manifest.name)
        var notes: [String] = []
        if let other = plan.otherSource { notes.append("The installed copy came from \(other.label); this one replaces it.") }
        var title = "Install “\(name)”?", action = "Install", added: [String] = []
        switch plan.kind {
        case .update(let from, let permissions): title = "Update “\(name)” from \(from) to \(package.manifest.version)?"; action = "Update"; added = permissions
        case .reinstall: title = "Reinstall “\(name)” \(package.manifest.version)?"; action = "Reinstall"
        case .downgrade(let from): title = "Replace “\(name)” \(from) with the older \(package.manifest.version)?"; action = "Replace"
        case .fresh: break
        }
        let consented = await ask(InstallSheetView(name: name, manifest: package.manifest, source: package.source.label, title: title,
                                                   actionTitle: action, notes: notes, newPermissions: added))
        if consented { await finish(plan, consented: true) }
    }

    /// Shows the sheet in its own window and waits for Install or Cancel.
    func ask(_ view: InstallSheetView) async -> Bool {
        await withCheckedContinuation { continuation in
            var answered = false
            let respond: (Bool) -> Void = { [weak self] value in
                guard !answered else { return }
                answered = true
                self?.sheet?.close()
                self?.sheet = nil
                continuation.resume(returning: value)
            }
            var sheetView = view
            sheetView.onInstall = { respond(true) }
            sheetView.onCancel = { respond(false) }
            let window = NSWindow(contentViewController: NSHostingController(rootView: sheetView))
            window.title = "Install Plugin"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            sheet = window
            NSApp.activate(ignoringOtherApps: true)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { respond(false) }
            }
        }
    }

    private func finish(_ plan: InstallPlan, consented: Bool) async {
        do {
            try await controller.installer.install(plan, consented: consented)
            await controller.reload()
            if case .fresh = plan.kind { await controller.runInstallHook(plan.package.manifest.id) }
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "The plugin can't be installed."
        alert.informativeText = (error as? InstallError)?.description ?? "\(error)"
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("baron-install-\(UUID().uuidString)")
    }

    /// `baron://install?url=https://…`: the package to download; HTTPS only.
    static func linkTarget(_ url: URL) -> URL? {
        guard url.host == "install", let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
              let download = URL(string: target), download.scheme == "https" else { return nil }
        return download
    }

    private func download(_ link: URL) async throws -> URL {
        guard let target = Self.linkTarget(link) else { throw InstallError("Install links need an https URL: baron://install?url=https://…") }
        let (file, response) = try await URLSession.shared.download(from: target)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError("The download failed.") }
        let destination = scratch().appendingPathExtension("baronplugin")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }
}
