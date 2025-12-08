//
//  LetterEditorView.swift
//  lifelog
//
//  Created by AI for Letter to the Future feature
//

import SwiftUI
import PhotosUI

struct LetterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppDataStore
    
    private let existingLetter: Letter?
    
    @State private var content: String
    @State private var deliveryType: LetterDeliveryType
    @State private var fixedDate: Date
    @State private var useDateRange: Bool
    @State private var randomStartDate: Date
    @State private var randomEndDate: Date
    @State private var useTimeRange: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var photoPaths: [String]
    
    // Photo picker
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    
    @State private var showDeleteConfirmation = false
    @State private var showSendConfirmation = false
    
    init(letter: Letter? = nil) {
        self.existingLetter = letter
        _content = State(initialValue: letter?.content ?? "")
        _deliveryType = State(initialValue: letter?.deliveryType ?? .fixed)
        
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _fixedDate = State(initialValue: letter?.deliveryDate ?? tomorrow)
        
        let settings = letter?.randomSettings
        _useDateRange = State(initialValue: settings?.useDateRange ?? false)
        _randomStartDate = State(initialValue: settings?.startDate ?? tomorrow)
        
        let threeMonthsLater = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        _randomEndDate = State(initialValue: settings?.endDate ?? threeMonthsLater)
        
        _useTimeRange = State(initialValue: settings?.useTimeRange ?? false)
        
        // 時間を Date として扱う
        let calendar = Calendar.current
        let startHour = settings?.startHour ?? 9
        let startMinute = settings?.startMinute ?? 0
        let endHour = settings?.endHour ?? 21
        let endMinute = settings?.endMinute ?? 0
        
        _startTime = State(initialValue: calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: Date()) ?? Date())
        _endTime = State(initialValue: calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: Date()) ?? Date())
        
        _photoPaths = State(initialValue: letter?.photoPaths ?? [])
    }
    
    var body: some View {
        Form {
            contentSection
            photoSection
            deliverySection
            deleteSection
        }
        .navigationTitle(existingLetter == nil ? "新しい手紙" : "手紙を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("封印する") {
                    showSendConfirmation = true
                }
                .disabled(content.isEmpty)
            }
        }
        .confirmationDialog("手紙を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let letter = existingLetter {
                    store.deleteLetter(letter.id)
                }
                dismiss()
            }
        }
        .alert("未来の自分に手紙を送りますか？", isPresented: $showSendConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("送る") {
                saveLetter()
            }
        } message: {
            Text(deliveryConfirmationMessage)
        }
        .onChange(of: selectedItems) { _, newItems in
            loadPhotos(from: newItems)
        }
        .task {
            // 既存の写真を読み込む
            await loadExistingPhotos()
        }
    }
    
    private var contentSection: some View {
        Section {
            TextEditor(text: $content)
                .frame(minHeight: 200)
        } header: {
            Text("手紙の内容")
        } footer: {
            Text("未来の自分に向けてメッセージを書きましょう")
        }
    }
    
    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 10, matching: .images) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(selectedImages.isEmpty ? "写真を追加（最大10枚）" : "\(selectedImages.count)枚選択中")
                }
            }
            
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            Image(uiImage: selectedImages[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(height: 90)
            }
        } header: {
            Text("写真")
        }
    }
    
    private var deliverySection: some View {
        Section {
            Picker("配達タイプ", selection: $deliveryType) {
                ForEach(LetterDeliveryType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            if deliveryType == .fixed {
                DatePicker("開封日時", selection: $fixedDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            } else {
                // ランダム設定
                Toggle("期間を指定する", isOn: $useDateRange)
                
                if useDateRange {
                    DatePicker("開始日", selection: $randomStartDate, in: Date()..., displayedComponents: .date)
                    DatePicker("終了日", selection: $randomEndDate, in: randomStartDate..., displayedComponents: .date)
                }
                
                Toggle("時間帯を指定する", isOn: $useTimeRange)
                
                if useTimeRange {
                    DatePicker("開始時刻", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("終了時刻", selection: $endTime, displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Text("開封日時の設定")
        } footer: {
            if deliveryType == .random {
                Text("期間・時間帯を指定しない場合は、1日後〜3年後の間でランダムに届きます。サプライズ感を楽しみましょう！")
            }
        }
    }
    
    /// 送信確認ダイアログ用のメッセージ
    private var deliveryConfirmationMessage: String {
        var lines: [String] = []
        
        if deliveryType == .fixed {
            // 固定日時
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M月d日 H:mm"
            lines.append("📅 \(formatter.string(from: fixedDate)) に届きます")
        } else {
            // ランダム
            if useDateRange || useTimeRange {
                var parts: [String] = []
                
                if useDateRange {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "ja_JP")
                    formatter.dateFormat = "M/d"
                    parts.append("\(formatter.string(from: randomStartDate))〜\(formatter.string(from: randomEndDate))")
                }
                
                if useTimeRange {
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "H:mm"
                    parts.append("\(timeFormatter.string(from: startTime))〜\(timeFormatter.string(from: endTime))")
                }
                
                lines.append("🎲 \(parts.joined(separator: " ")) の間に届きます")
            } else {
                // 完全ランダム
                lines.append("✨ いつか届きます（1日後〜3年後）")
            }
        }
        
        lines.append("")
        lines.append("届くまで編集・削除ができません。")
        
        return lines.joined(separator: "\n")
    }
    
    @ViewBuilder
    private var deleteSection: some View {
        if existingLetter != nil {
            Section {
                Button("この手紙を削除", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
    }
    
    private func loadPhotos(from items: [PhotosPickerItem]) {
        selectedImages = []
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        selectedImages.append(image)
                    }
                }
            }
        }
    }
    
    private func loadExistingPhotos() async {
        // 既存の写真パスから画像を読み込む
        for path in photoPaths {
            if let data = FileManager.default.contents(atPath: path),
               let image = UIImage(data: data) {
                await MainActor.run {
                    selectedImages.append(image)
                }
            }
        }
    }
    
    private func savePhotos(letterId: UUID) -> [String] {
        var paths: [String] = []
        
        // Letters 用のディレクトリを取得/作成
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return paths
        }
        
        let relativeDirPath = "Letters/\(letterId.uuidString)"
        let lettersDir = documentsDir.appendingPathComponent(relativeDirPath, isDirectory: true)
        
        // ディレクトリを作成
        try? FileManager.default.createDirectory(at: lettersDir, withIntermediateDirectories: true)
        
        // 各画像を保存
        for (index, image) in selectedImages.enumerated() {
            if let data = image.jpegData(compressionQuality: 0.8) {
                let fileName = "photo_\(index).jpg"
                let filePath = lettersDir.appendingPathComponent(fileName)
                
                do {
                    try data.write(to: filePath)
                    // 相対パスを保存（リビルド後も有効）
                    paths.append("\(relativeDirPath)/\(fileName)")
                } catch {
                    print("写真保存エラー: \(error)")
                }
            }
        }
        
        return paths
    }
    
    private func saveLetter() {
        var letter: Letter
        
        if let existing = existingLetter {
            letter = existing
            letter.content = content
            letter.deliveryType = deliveryType
        } else {
            letter = Letter(
                content: content,
                deliveryType: deliveryType
            )
        }
        
        // 写真を保存してパスを設定
        letter.photoPaths = savePhotos(letterId: letter.id)
        
        if deliveryType == .fixed {
            letter.deliveryDate = fixedDate
            letter.randomSettings = nil
        } else {
            let calendar = Calendar.current
            letter.randomSettings = LetterRandomSettings(
                useDateRange: useDateRange,
                startDate: useDateRange ? randomStartDate : nil,
                endDate: useDateRange ? randomEndDate : nil,
                useTimeRange: useTimeRange,
                startHour: calendar.component(.hour, from: startTime),
                startMinute: calendar.component(.minute, from: startTime),
                endHour: calendar.component(.hour, from: endTime),
                endMinute: calendar.component(.minute, from: endTime)
            )
        }
        
        if existingLetter != nil {
            store.updateLetter(letter)
            store.sealLetter(letter.id)
        } else {
            store.addLetter(letter)
            store.sealLetter(letter.id)
        }
        
        HapticManager.success()
        dismiss()
    }
}
