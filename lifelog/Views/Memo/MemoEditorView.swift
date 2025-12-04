//
//  MemoEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/15.
//

import SwiftUI

struct MemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemoPadViewModel

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: MemoPadViewModel(store: store))
    }

    private var memoBinding: Binding<String> {
        Binding(
            get: { viewModel.memoText },
            set: { viewModel.update(text: $0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: memoBinding)
                        .keyboardType(.default)
                        .frame(minHeight: 340, alignment: .topLeading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .scrollContentBackground(.hidden)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let lastUpdated = viewModel.lastUpdatedAt {
                    Text("最終更新: \(lastUpdated.memoPadDisplayString())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding()
        }
        .navigationTitle("メモ")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    dismiss()
                }
            }
        }
    }
}
