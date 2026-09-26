//
//  PhotoStorageSettingsView.swift
//  lifelog
//
//  Diary photo storage choices: docs/diary-photo-icloud-sync.md.
//

import SwiftUI

struct PhotoStorageSettingsView: View {
    @EnvironmentObject private var store: AppDataStore
    @ObservedObject private var sync = PhotoCloudSyncService.shared
    @State private var localStorageSize: Int64 = 0
    @State private var storageRefreshID = 0

    private var canUseCloud: Bool {
        !PersistenceController.isSimulatorDemoMode &&
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" &&
            !ProcessInfo.processInfo.arguments.contains("-screenshots-mode") &&
            !ProcessInfo.processInfo.arguments.contains("-ScreenshotsMode")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("photoStorage.localUsage") {
                    Text(ByteCountFormatter.string(fromByteCount: localStorageSize, countStyle: .file))
                        .monospacedDigit()
                }
            } footer: {
                Text("photoStorage.overview")
            }

            storageModeSection
            syncSection

            Section {
                Label {
                    Text("photoStorage.icloudAccount")
                } icon: {
                    Image(systemName: "person.crop.circle")
                }
                Label {
                    Text("photoStorage.icloudSpace")
                } icon: {
                    Image(systemName: "icloud")
                }
                Label {
                    Text("photoStorage.deletion")
                } icon: {
                    Image(systemName: "trash")
                }
            } header: {
                Text("photoStorage.about")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("photoStorage.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            configurePhotos()
        }
        .task(id: storageRefreshID) {
            await refreshLocalStorageSize()
        }
        .onChange(of: store.allDiaryPhotoPaths) { _, _ in
            configurePhotos()
            storageRefreshID += 1
        }
        .onChange(of: sync.isSyncing) { _, _ in
            storageRefreshID += 1
        }
    }

    private var storageModeSection: some View {
        Section {
            storageModeRow(
                .optimizeStorage,
                title: "photoStorage.mode.optimize",
                detail: "photoStorage.mode.optimize.description"
            )
            storageModeRow(
                .keepAllLocal,
                title: "photoStorage.mode.keepAll",
                detail: "photoStorage.mode.keepAll.description"
            )
        } header: {
            Text("photoStorage.mode.title")
        } footer: {
            Text("photoStorage.mode.unsynced")
        }
    }

    private func storageModeRow(
        _ mode: PhotoStorageMode,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        Button {
            guard canUseCloud else { return }
            sync.setMode(mode)
            storageRefreshID += 1
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: sync.mode == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(sync.mode == mode ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canUseCloud || sync.isSyncing)
        .accessibilityAddTraits(sync.mode == mode ? .isSelected : [])
        .accessibilityIdentifier("photoStorage.mode.\(mode.rawValue)")
    }

    private var syncSection: some View {
        Section {
            if !sync.isEnabled {
                Label("photoStorage.status.notStarted", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("photoStorage.syncedCount") {
                Text(sync.syncedCount, format: .number)
                    .monospacedDigit()
            }
            LabeledContent("photoStorage.pendingCount") {
                Text(sync.pendingCount, format: .number)
                    .monospacedDigit()
            }

            if sync.isSyncing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("photoStorage.status.syncing")
                    ProgressView(
                        value: Double(min(sync.completedCount, sync.totalCount)),
                        total: Double(max(sync.totalCount, 1))
                    )
                    Text(verbatim: "\(sync.completedCount) / \(sync.totalCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if sync.isEnabled && sync.pendingCount == 0 && sync.lastError == nil {
                Label("photoStorage.status.synced", systemImage: "checkmark.icloud")
                    .foregroundStyle(.secondary)
            }

            if let error = sync.lastError {
                Label {
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.icloud")
                }
                .font(.footnote)
                .foregroundStyle(.orange)

                Button("photoStorage.retry") {
                    guard canUseCloud else { return }
                    configurePhotos()
                    if sync.isEnabled {
                        sync.resumeSync()
                    } else {
                        sync.startSync()
                    }
                }
                .disabled(!canUseCloud || sync.isSyncing)
            }

            Button {
                guard canUseCloud else { return }
                configurePhotos()
                sync.startSync()
            } label: {
                Label("photoStorage.syncAll", systemImage: "icloud.and.arrow.up")
            }
            .disabled(!canUseCloud || sync.isSyncing || store.allDiaryPhotoPaths.isEmpty)
            .accessibilityIdentifier("photoStorage.syncAll")
        } header: {
            Text("photoStorage.sync.title")
        } footer: {
            Text("photoStorage.sync.description")
        }
    }

    private func configurePhotos() {
        guard canUseCloud else { return }
        sync.configure(paths: store.allDiaryPhotoPaths)
    }

    private func refreshLocalStorageSize() async {
        let scan = _Concurrency.Task.detached(priority: .utility) {
            PhotoStorage.totalStorageSize()
        }
        let size = await withTaskCancellationHandler {
            await scan.value
        } onCancel: {
            scan.cancel()
        }
        // A replaced task or a dismissed view must not publish a stale scan result.
        guard !_Concurrency.Task.isCancelled else { return }
        localStorageSize = size
    }
}
