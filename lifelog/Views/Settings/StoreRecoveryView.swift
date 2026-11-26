import SwiftData
import SwiftUI
import WidgetKit

struct StoreRecoveryView: View {
    private enum ScanState {
        case loading
        case ready([StoreRecoveryCandidate])
        case unavailable
    }

    @State private var state = ScanState.loading
    @State private var scan = 0

    var body: some View {
        ZStack {
            switch state {
            case .loading:
                List { ProgressView { Text("recovery.scanning", tableName: "StoreRecovery") } }
            case .unavailable:
                List {
                    Text("recovery.scanFailed", tableName: "StoreRecovery")
                    Button { scan += 1 } label: { Text("recovery.retry", tableName: "StoreRecovery") }
                }
            case .ready(let candidates):
                if candidates.isEmpty {
                    List { Text("recovery.empty", tableName: "StoreRecovery") }
                } else if candidates.count == 1, let candidate = candidates.first {
                    StoreRecoveryDetails(candidate: candidate)
                } else {
                    List {
                        Section {
                            ForEach(candidates) { candidate in
                                NavigationLink {
                                    StoreRecoveryDetails(candidate: candidate)
                                } label: {
                                    Text(candidate.date, format: .dateTime.year().month().day().hour().minute().second())
                                }
                            }
                        } header: {
                            Text("recovery.archives", tableName: "StoreRecovery")
                        } footer: {
                            Text("recovery.select", tableName: "StoreRecovery")
                        }
                    }
                }
            }
        }
        .appThemeBackground()
        .navigationTitle(Text("recovery.title", tableName: "StoreRecovery"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scan) {
            state = .loading
            let service = StoreRecoveryService()
            do {
                let candidates = try await _Concurrency.Task.detached(priority: .userInitiated) {
                    try service.candidates()
                }.value
                try _Concurrency.Task.checkCancellation()
                state = .ready(candidates)
            } catch is CancellationError {
                return
            } catch {
                state = .unavailable
            }
        }
    }
}

private struct StoreRecoveryDetails: View {
    private enum Phase {
        case inspecting
        case preview(StoreRecoverySummary)
        case restoring
        case complete(Int, needsRelaunch: Bool)
        case failed(LocalizedStringKey)
    }

    let candidate: StoreRecoveryCandidate
    @EnvironmentObject private var store: AppDataStore
    @State private var phase = Phase.inspecting
    @State private var inspection = 0
    @State private var showConfirmation = false

    private var isRestoring: Bool {
        if case .restoring = phase { return true }
        return false
    }

    var body: some View {
        List {
            Section {
                Text(candidate.date, format: .dateTime.year().month().day().hour().minute().second())
            } header: {
                Text("recovery.archivedAt", tableName: "StoreRecovery")
            }
            switch phase {
            case .inspecting:
                ProgressView { Text("recovery.inspecting", tableName: "StoreRecovery") }
            case .preview(let summary):
                Section {
                    recordCount("recovery.diaries", summary.diaryEntries)
                    recordCount("recovery.events", summary.events)
                    recordCount("recovery.tasks", summary.tasks)
                    recordCount("recovery.other", summary.otherRecords)
                } header: {
                    Text("recovery.preview", tableName: "StoreRecovery")
                }
                Section {
                    if summary.total > 0 {
                        Button {
                            showConfirmation = true
                        } label: {
                            Text("recovery.action", tableName: "StoreRecovery")
                        }
                    } else {
                        Text("recovery.noRecords", tableName: "StoreRecovery")
                    }
                } footer: {
                    if summary.total > 0 {
                        Text("recovery.explanation", tableName: "StoreRecovery")
                    }
                }
            case .restoring:
                ProgressView { Text("recovery.restoring", tableName: "StoreRecovery") }
            case .complete(let count, let needsRelaunch):
                if count == 0 {
                    Text("recovery.noAdditions", tableName: "StoreRecovery")
                } else {
                    Text("recovery.success.count \(count)", tableName: "StoreRecovery")
                }
                if needsRelaunch {
                    Text("recovery.reloadFailed", tableName: "StoreRecovery")
                }
            case .failed(let message):
                Text(message, tableName: "StoreRecovery")
                Button { inspection += 1 } label: { Text("recovery.retry", tableName: "StoreRecovery") }
            }
        }
        .appThemeBackground()
        .navigationTitle(Text("recovery.title", tableName: "StoreRecovery"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isRestoring)
        .interactiveDismissDisabled(isRestoring)
        .alert(Text("recovery.confirmTitle", tableName: "StoreRecovery"), isPresented: $showConfirmation) {
            Button(role: .cancel) {} label: { Text("recovery.cancel", tableName: "StoreRecovery") }
            Button { _Concurrency.Task { await restore() } } label: {
                Text("recovery.action", tableName: "StoreRecovery")
            }
        } message: {
            Text("recovery.explanation", tableName: "StoreRecovery")
        }
        .task(id: inspection) {
            phase = .inspecting
            let service = StoreRecoveryService()
            do {
                let summary = try await _Concurrency.Task.detached(priority: .userInitiated) { [candidate] in
                    try service.inspect(candidate)
                }.value
                try _Concurrency.Task.checkCancellation()
                phase = .preview(summary)
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(message(for: error, fallback: "recovery.unreadableArchive"))
            }
        }
    }

    private func recordCount(_ label: LocalizedStringKey, _ count: Int) -> some View {
        LabeledContent {
            Text(count, format: .number)
        } label: {
            Text(label, tableName: "StoreRecovery")
        }
    }

    @MainActor
    private func restore() async {
        guard case .preview = phase else { return }
        phase = .restoring
        let service = StoreRecoveryService()
        do {
            let (count, needsRelaunch) = try await _Concurrency.Task.detached(priority: .userInitiated) { [candidate, store] in
                try service.withRecoveredStore(candidate) { context in
                    let source = context.container
                    // Keep the scratch copy alive until the main-actor import has saved.
                    return try DispatchQueue.main.sync { () -> (Int, Bool) in
                        if store.modelContext.hasChanges { try store.modelContext.save() }
                        let count = try RecoveredRecordImporter.restore(from: source, into: store.modelContext.container)
                        guard count > 0 else { return (0, false) }
                        // Refresh before any background service can persist its pre-recovery snapshot.
                        do {
                            try store.reloadAfterStoreRecovery()
                            return (count, false)
                        } catch {
                            return (count, true)
                        }
                    }
                }
            }.value
            if count > 0 {
                WidgetCenter.shared.reloadAllTimelines()
            }
            phase = .complete(count, needsRelaunch: needsRelaunch)
        } catch {
            phase = .failed(message(for: error, fallback: "recovery.saveFailed"))
        }
    }

    private func message(for error: Error, fallback: LocalizedStringKey) -> LocalizedStringKey {
        switch error as? StoreRecoveryError {
        case .missingDatabase: "recovery.missingDatabase"
        case .invalidDatabase: "recovery.invalidDatabase"
        case .unreadableArchive: "recovery.unreadableArchive"
        case nil: fallback
        }
    }
}
