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

    private let placeholder = "なんでもメモするスペースです"

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: MemoPadViewModel(store: store))
    }

    private var memoBinding: Binding<String> {
        Binding(
            get: { viewModel.memoPad.text },
            set: { viewModel.update(text: $0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if viewModel.memoPad.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20) // slight offset to match TextEditor caret baseline
                    }
                    TextEditor(text: memoBinding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .scrollContentBackground(.hidden)
                }
                .frame(height: 600)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let lastUpdated = viewModel.memoPad.lastUpdatedAt {
                    Text("最終更新: \(lastUpdated.memoPadDisplayString())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding()
        }
        .navigationTitle("メモ")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    dismiss()
                }
            }
        }
    }
}
