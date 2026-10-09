import AppKit
import BaronCore
import BaronPlatform
import SwiftUI

/// Holds the latest debug snapshot for the panel.
@MainActor
final class DebugStore: ObservableObject {
    @Published var snapshot: DebugSnapshot?

    /// Reads the full context of the selection (no copy steps) and publishes it.
    func record(trigger: Trigger, outcome: PipelineOutcome, source: FocusedSelectionSource) async {
        var report: ProbeReport?
        if case .show = outcome {
            report = await SelectionProbe.run(on: source.app, includeCopy: false)
        }
        snapshot = DebugSnapshot.make(
            outcome: outcome, trigger: trigger, appName: source.app.localizedName,
            bundleIdentifier: source.bundleIdentifier, report: report
        )
    }
}

struct DebugView: View {
    @ObservedObject var store: DebugStore

    var body: some View {
        if let snapshot = store.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(snapshot.date.formatted(date: .omitted, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(snapshot.rows, id: \.label) { row in
                            GridRow {
                                Text(row.label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(row.value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                Text(row.milliseconds.map { String(format: "%.1f ms", $0) } ?? "")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Text(snapshot.summary).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Select text in any app.\nWhat Baron reads appears here.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A floating utility panel that never takes focus, so it can't disturb the selection it reports on.
@MainActor
final class DebugPanelController {
    let store = DebugStore()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.title = "\(Baron.name) Debug"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: DebugView(store: store))
        panel.setAccessibilityIdentifier("baron.debug")
        panel.setFrameAutosaveName("BaronDebugPanel")
        if !panel.setFrameUsingName("BaronDebugPanel") { panel.center() }
        return panel
    }()

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
