import BaronCore
import Foundation

/// What installing a package would do. Design: 10-install-and-lifecycle.md
public enum InstallKind: Equatable, Sendable {
    case fresh
    /// A higher version; installs silently unless it adds permissions.
    case update(from: String, addsPermissions: [String])
    /// The same version again: asks first.
    case reinstall
    /// A lower version: asks first.
    case downgrade(from: String)
}

public struct InstallPlan: Sendable {
    public var package: PluginPackage
    public var kind: InstallKind
    /// Set when the installed copy came from somewhere else: the sheet warns.
    public var otherSource: PluginSource?

    /// Whether the user is asked before installing.
    public var needsSheet: Bool {
        switch kind {
        case .fresh, .reinstall, .downgrade: true
        case .update(_, let added): !added.isEmpty
        }
    }
}

/// An update waiting for the user to accept its new permissions; the installed version keeps working.
public struct PendingUpdate: Codable, Equatable, Sendable {
    public var version: String
    public var newPermissions: [String]
    public var source: PluginSource
}

public struct InstalledRecord: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var source: PluginSource
    /// Kept until the new version first runs, then deleted.
    public var previousVersion: String?
    public var pending: PendingUpdate?
}

public struct InstalledPlugin: Sendable {
    public var record: InstalledRecord
    public var plugin: RuntimePlugin
}

/// Installs, updates and uninstalls plugins under `Plugins/<id>/<version>/`, recorded in `Plugins/installed.json`.
/// Installed versions are never modified. Design: 10-install-and-lifecycle.md
public actor PluginInstaller {
    nonisolated public let root: URL
    private let data: PluginDataManager
    private var records: [String: InstalledRecord]

    public static var standardRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Baron.name).appendingPathComponent("Plugins")
    }

    public init(root: URL = PluginInstaller.standardRoot, data: PluginDataManager) {
        self.root = root
        self.data = data
        let registry = root.appendingPathComponent("installed.json")
        records = (try? JSONDecoder().decode([String: InstalledRecord].self, from: Data(contentsOf: registry))) ?? [:]
    }

    public func plan(_ package: PluginPackage) -> InstallPlan {
        let id = package.manifest.id
        guard let record = records[id], let installed = manifest(id, version: record.version) else {
            return InstallPlan(package: package, kind: .fresh, otherSource: nil)
        }
        let otherSource = Self.sameOrigin(record.source, package.source) ? nil : record.source
        let new = SemanticVersion(package.manifest.version), old = SemanticVersion(record.version)
        let kind: InstallKind
        if let new, let old, new > old {
            let added = (package.manifest.permissions + package.manifest.optionalPermissions)
                .filter { !(installed.permissions + installed.optionalPermissions).contains($0) }
            kind = .update(from: record.version, addsPermissions: added)
        } else if let new, let old, new < old {
            kind = .downgrade(from: record.version)
        } else {
            kind = .reinstall
        }
        return InstallPlan(package: package, kind: kind, otherSource: otherSource)
    }

    /// Copies the package and records it. An update that adds permissions waits as pending until `acceptPending`,
    /// unless `consented` (the user accepted them in the sheet).
    @discardableResult
    public func install(_ plan: InstallPlan, consented: Bool) throws -> InstalledRecord {
        let manifest = plan.package.manifest
        let destination = folder(manifest.id, version: manifest.version)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: plan.package.folder, to: destination)

        var record = records[manifest.id]
        switch plan.kind {
        case .update(let from, let added) where !added.isEmpty && !consented:
            record?.pending = PendingUpdate(version: manifest.version, newPermissions: added, source: plan.package.source)
            _ = from
        case .update(let from, _):
            record = InstalledRecord(id: manifest.id, version: manifest.version, source: plan.package.source, previousVersion: from, pending: nil)
        case .downgrade(let from):
            record = InstalledRecord(id: manifest.id, version: manifest.version, source: plan.package.source, previousVersion: from, pending: nil)
        case .fresh, .reinstall:
            record = InstalledRecord(id: manifest.id, version: manifest.version, source: plan.package.source, previousVersion: nil, pending: nil)
        }
        records[manifest.id] = record
        try save()
        return record!
    }

    /// The user accepted a pending update's new permissions: it becomes the installed version.
    public func acceptPending(_ id: String) throws {
        guard var record = records[id], let pending = record.pending else { return }
        record.previousVersion = record.version
        record.version = pending.version
        record.source = pending.source
        record.pending = nil
        records[id] = record
        try save()
    }

    /// The user kept the old version: the pending one is deleted.
    public func declinePending(_ id: String) throws {
        guard var record = records[id], let pending = record.pending else { return }
        try? FileManager.default.removeItem(at: folder(id, version: pending.version))
        record.pending = nil
        records[id] = record
        try save()
    }

    /// The new version ran: the previous one's folder goes.
    public func confirmLoaded(_ id: String) throws {
        guard var record = records[id], let previous = record.previousVersion else { return }
        if previous != record.version { try? FileManager.default.removeItem(at: folder(id, version: previous)) }
        record.previousVersion = nil
        records[id] = record
        try save()
    }

    /// Removes the package and all of its data: storage, cache, preferences, secrets and grants.
    public func uninstall(_ id: String) async throws {
        records[id] = nil
        try save()
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
        try await data.removeAll(id)
    }

    public func installed() -> [InstalledPlugin] {
        records.values.sorted { $0.id < $1.id }.compactMap { record in
            manifest(record.id, version: record.version).map {
                InstalledPlugin(record: record, plugin: RuntimePlugin(manifest: $0, package: folder(record.id, version: record.version)))
            }
        }
    }

    public func record(_ id: String) -> InstalledRecord? { records[id] }

    nonisolated public func folder(_ id: String, version: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true).appendingPathComponent(version, isDirectory: true)
    }

    private func manifest(_ id: String, version: String) -> PluginManifest? {
        ManifestValidator().validate(package: folder(id, version: version)).manifest
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: root.appendingPathComponent("installed.json"), options: .atomic)
    }

    /// Two sources are the same origin when they're the same kind and place (a folder and its re-pick count as one).
    static func sameOrigin(_ a: PluginSource, _ b: PluginSource) -> Bool {
        switch (a, b) {
        case (.bundled, .bundled): true
        case (.folder(let x), .folder(let y)), (.file(let x), .file(let y)), (.development(let x), .development(let y)): x == y
        case (.link(let x), .link(let y)): URL(string: x)?.host == URL(string: y)?.host
        default: false
        }
    }
}
