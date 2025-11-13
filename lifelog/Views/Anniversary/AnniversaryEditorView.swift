//
//  AnniversaryEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct AnniversaryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Anniversary) -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var type: AnniversaryType = .countdown
    @State private var repeatsYearly = false

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("タイトル", text: $title)
                DatePicker("日付", selection: $date, displayedComponents: .date)
                Picker("種類", selection: $type) {
                    ForEach(AnniversaryType.allCases) { type in
                        Text(type == .countdown ? "までの残り日数" : "経過日数").tag(type)
                    }
                }
                Toggle("毎年繰り返す", isOn: $repeatsYearly)
            }
        }
        .navigationTitle("記念日")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let item = Anniversary(title: title,
                                           targetDate: date,
                                           type: type,
                                           repeatsYearly: repeatsYearly)
                    onSave(item)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) { dismiss() }
            }
        }
    }
}
