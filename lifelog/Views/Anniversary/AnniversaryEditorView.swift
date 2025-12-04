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
    var onDelete: (() -> Void)?
    private var editingAnniversary: Anniversary?

    @State private var title: String
    @State private var date: Date
    @State private var type: AnniversaryType
    @State private var repeatsYearly: Bool
    @State private var showDeleteConfirmation = false

    init(anniversary: Anniversary? = nil,
         onSave: @escaping (Anniversary) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.editingAnniversary = anniversary
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: anniversary?.title ?? "")
        _date = State(initialValue: anniversary?.targetDate ?? Date())
        _type = State(initialValue: anniversary?.type ?? .countdown)
        _repeatsYearly = State(initialValue: anniversary?.repeatsYearly ?? false)
    }

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
            
            if editingAnniversary != nil && onDelete != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("記念日を削除")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(editingAnniversary == nil ? "記念日を追加" : "記念日を編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let item = Anniversary(
                        id: editingAnniversary?.id ?? UUID(),
                        title: title,
                        targetDate: date,
                        type: type,
                        repeatsYearly: repeatsYearly
                    )
                    onSave(item)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) { dismiss() }
            }
        }
        .confirmationDialog("この記念日を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }
}
