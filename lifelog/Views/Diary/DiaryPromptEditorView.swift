//
//  DiaryPromptEditorView.swift
//  lifelog
//
//  Created by Codex on 2026/01/05.
//

import SwiftUI

/// 日記AI採点用プロンプトの編集画面
struct DiaryPromptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var prompt: String
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextEditor(text: $prompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 400)
                } header: {
                    Text("AI採点プロンプト")
                } footer: {
                    Text("日記本文はプロンプトの末尾に自動で追加されます")
                }
                
                Section {
                    Button("デフォルトに戻す") {
                        prompt = DiaryScorePrompt.defaultPrompt
                        HapticManager.light()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("プロンプト編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}
