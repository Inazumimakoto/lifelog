//
//  MemoEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/15.
//

import SwiftUI

struct MemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: MemoPadViewModel

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: MemoPadViewModel(store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                MemoTextView(initialText: viewModel.textDraft) { newValue in
                    viewModel.update(text: newValue)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(viewModel.lastUpdatedAt == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .navigationTitle("メモ")
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .scrollDismissesKeyboard(.never)
        .onDisappear {
            viewModel.flushPendingSave()
        }
        .onChange(of: scenePhase, initial: false) { _, newPhase in
            if newPhase != .active {
                viewModel.flushPendingSave()
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    viewModel.flushPendingSave()
                    dismiss()
                }
            }
        }
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = viewModel.lastUpdatedAt else { return "最終更新: -" }
        return "最終更新: \(lastUpdated.memoPadDisplayString())"
    }
}
