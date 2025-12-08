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
    
    // 日付設定
    @State private var dateMode: DeliveryMode  // 固定 or ランダム
    @State private var fixedDate: Date
    @State private var useDateRange: Bool
    @State private var randomStartDate: Date
    @State private var randomEndDate: Date
    
    // 時間設定
    @State private var timeMode: DeliveryMode  // 固定 or ランダム
    @State private var fixedTime: Date
    @State private var useTimeRange: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    
    @State private var photoPaths: [String]
    
    // Photo picker
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    
    @State private var showDeleteConfirmation = false
    @State private var showSendConfirmation = false
    
    enum DeliveryMode: String, CaseIterable, Identifiable {
        case fixed = "固定"
        case random = "ランダム"
        var id: String { rawValue }
    }
    
    init(letter: Letter? = nil) {
        self.existingLetter = letter
        _content = State(initialValue: letter?.content ?? "")
        
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let threeMonthsLater = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        let calendar = Calendar.current
        
        // 既存の手紙から設定を復元
        if let letter = letter {
            if letter.deliveryType == .fixed {
                // 両方固定
                _dateMode = State(initialValue: .fixed)
                _timeMode = State(initialValue: .fixed)
                _fixedDate = State(initialValue: letter.deliveryDate)
                _fixedTime = State(initialValue: letter.deliveryDate)
                // ランダム用のデフォルト値も初期化
                _useDateRange = State(initialValue: false)
                _randomStartDate = State(initialValue: tomorrow)
                _randomEndDate = State(initialValue: threeMonthsLater)
                _useTimeRange = State(initialValue: false)
                _startTime = State(initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
                _endTime = State(initialValue: calendar.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date())
            } else {
                // ランダム設定を復元
                let settings = letter.randomSettings
                let hasDateRange = settings?.useDateRange ?? false
                let hasTimeRange = settings?.useTimeRange ?? false
                
                // 日付モードの判定（fixedDateがあれば固定モード）
                let isDateFixed = settings?.fixedDate != nil
                _dateMode = State(initialValue: isDateFixed ? .fixed : .random)
                _useDateRange = State(initialValue: hasDateRange)
                _randomStartDate = State(initialValue: settings?.startDate ?? tomorrow)
                _randomEndDate = State(initialValue: settings?.endDate ?? threeMonthsLater)
                _fixedDate = State(initialValue: settings?.fixedDate ?? tomorrow)
                
                // 時間モードの判定（fixedHourがあれば固定モード）
                let isTimeFixed = settings?.fixedHour != nil
                _timeMode = State(initialValue: isTimeFixed ? .fixed : .random)
                _useTimeRange = State(initialValue: hasTimeRange)
                let startHour = settings?.startHour ?? 9
                let startMinute = settings?.startMinute ?? 0
                let endHour = settings?.endHour ?? 21
                let endMinute = settings?.endMinute ?? 0
                _startTime = State(initialValue: calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: Date()) ?? Date())
                _endTime = State(initialValue: calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: Date()) ?? Date())
                
                let fixedHour = settings?.fixedHour ?? 12
                let fixedMinute = settings?.fixedMinute ?? 0
                _fixedTime = State(initialValue: calendar.date(bySettingHour: fixedHour, minute: fixedMinute, second: 0, of: Date()) ?? Date())
            }
        } else {
            // 新規作成のデフォルト
            _dateMode = State(initialValue: .fixed)
            _timeMode = State(initialValue: .fixed)
            _fixedDate = State(initialValue: tomorrow)
            _fixedTime = State(initialValue: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date())
            _useDateRange = State(initialValue: false)
            _randomStartDate = State(initialValue: tomorrow)
            _randomEndDate = State(initialValue: threeMonthsLater)
            _useTimeRange = State(initialValue: false)
            _startTime = State(initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
            _endTime = State(initialValue: calendar.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date())
        }
        
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
        Group {
            // 日付設定セクション
            Section {
                Picker("日付", selection: $dateMode) {
                    ForEach(DeliveryMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                if dateMode == .fixed {
                    DatePicker("開封日", selection: $fixedDate, in: Date()..., displayedComponents: .date)
                } else {
                    Toggle("期間を指定する", isOn: $useDateRange)
                    
                    if useDateRange {
                        DatePicker("開始日", selection: $randomStartDate, in: Date()..., displayedComponents: .date)
                        DatePicker("終了日", selection: $randomEndDate, in: randomStartDate..., displayedComponents: .date)
                    }
                }
            } header: {
                Text("📅 日付の設定")
            } footer: {
                if dateMode == .random {
                    if useDateRange {
                        Text("指定した期間内のどこかの日に届きます")
                    } else {
                        Text("💡 期間を指定しない場合、1日後〜3年後の間でサプライズ配達されます")
                    }
                }
            }
            
            // 時間設定セクション
            Section {
                Picker("時間", selection: $timeMode) {
                    ForEach(DeliveryMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                if timeMode == .fixed {
                    DatePicker("開封時刻", selection: $fixedTime, displayedComponents: .hourAndMinute)
                } else {
                    Toggle("時間帯を指定する", isOn: $useTimeRange)
                    
                    if useTimeRange {
                        DatePicker("開始時刻", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("終了時刻", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }
            } header: {
                Text("⏰ 時間の設定")
            } footer: {
                if timeMode == .random {
                    if useTimeRange {
                        Text("指定した時間帯のどこかの時刻に届きます")
                    } else {
                        Text("💡 時間帯を指定しない場合、終日いつでも届く可能性があります")
                    }
                }
            }
        }
    }
    
    /// 送信確認ダイアログ用のメッセージ
    private var deliveryConfirmationMessage: String {
        var lines: [String] = []
        
        // 日付部分
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "M月d日"
        
        var datePart: String
        if dateMode == .fixed {
            datePart = dateFormatter.string(from: fixedDate)
        } else if useDateRange {
            dateFormatter.dateFormat = "M/d"
            datePart = "\(dateFormatter.string(from: randomStartDate))〜\(dateFormatter.string(from: randomEndDate))"
        } else {
            datePart = "1日後〜3年後"
        }
        
        // 時間部分
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "H:mm"
        
        var timePart: String
        if timeMode == .fixed {
            timePart = timeFormatter.string(from: fixedTime)
        } else if useTimeRange {
            timePart = "\(timeFormatter.string(from: startTime))〜\(timeFormatter.string(from: endTime))"
        } else {
            timePart = "終日"
        }
        
        // メッセージ組み立て
        if dateMode == .fixed && timeMode == .fixed {
            lines.append("📅 \(datePart) \(timePart) に届きます")
        } else if dateMode == .random && timeMode == .random && !useDateRange && !useTimeRange {
            lines.append("✨ いつか届きます（1日後〜3年後）")
        } else {
            lines.append("🎲 \(datePart) \(timePart) に届きます")
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
        
        // deliveryType を判定：両方固定なら .fixed、それ以外は .random
        let computedDeliveryType: LetterDeliveryType = (dateMode == .fixed && timeMode == .fixed) ? .fixed : .random
        
        if let existing = existingLetter {
            letter = existing
            letter.content = content
            letter.deliveryType = computedDeliveryType
        } else {
            letter = Letter(
                content: content,
                deliveryType: computedDeliveryType
            )
        }
        
        // 写真を保存してパスを設定
        letter.photoPaths = savePhotos(letterId: letter.id)
        
        let calendar = Calendar.current
        
        if computedDeliveryType == .fixed {
            // 両方固定：固定日付 + 固定時刻を組み合わせ
            var components = calendar.dateComponents([.year, .month, .day], from: fixedDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: fixedTime)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            letter.deliveryDate = calendar.date(from: components) ?? fixedDate
            letter.randomSettings = nil
        } else {
            // 少なくとも1つがランダム
            let settings = LetterRandomSettings(
                useDateRange: dateMode == .random && useDateRange,
                startDate: (dateMode == .random && useDateRange) ? randomStartDate : nil,
                endDate: (dateMode == .random && useDateRange) ? randomEndDate : nil,
                useTimeRange: timeMode == .random && useTimeRange,
                startHour: calendar.component(.hour, from: startTime),
                startMinute: calendar.component(.minute, from: startTime),
                endHour: calendar.component(.hour, from: endTime),
                endMinute: calendar.component(.minute, from: endTime),
                // 新しいフィールド：固定日付・固定時刻
                fixedDate: dateMode == .fixed ? fixedDate : nil,
                fixedHour: timeMode == .fixed ? calendar.component(.hour, from: fixedTime) : nil,
                fixedMinute: timeMode == .fixed ? calendar.component(.minute, from: fixedTime) : nil
            )
            letter.randomSettings = settings
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
