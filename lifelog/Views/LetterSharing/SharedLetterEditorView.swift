//
//  SharedLetterEditorView.swift
//  lifelog
//
//  大切な人への手紙 - 手紙作成画面
//  既存のLetterEditorViewを基に、送信先選択と最終ログイン配信条件を追加
//

import SwiftUI
import PhotosUI

/// 共有手紙の作成・編集画面
struct SharedLetterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pairingService = PairingService.shared
    @ObservedObject private var authService = AuthService.shared
    
    // 送信先
    @State private var selectedFriend: PairingService.Friend?
    @State private var showingFriendPicker = false
    
    // 手紙の内容
    @State private var content: String = ""
    
    // 配信モード
    @State private var deliveryCondition: DeliveryCondition = .fixedDate
    
    // 日付設定
    @State private var dateMode: DateMode = .fixed
    @State private var fixedDate: Date
    @State private var useDateRange: Bool = false
    @State private var randomStartDate: Date
    @State private var randomEndDate: Date
    
    // 時間設定
    @State private var timeMode: TimeMode = .fixed
    @State private var fixedTime: Date
    @State private var useTimeRange: Bool = false
    @State private var startTime: Date
    @State private var endTime: Date
    
    // 最終ログイン設定
    @State private var lastLoginDays: Int = 7
    
    // 写真
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    
    // UI状態
    @State private var showSendConfirmation = false
    @State private var isSending = false
    @State private var errorMessage: String?
    
    // MARK: - Enums
    
    enum DeliveryCondition: String, CaseIterable, Identifiable {
        case fixedDate = "日時指定"
        case random = "ランダム"
        case lastLogin = "最終ログイン"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .fixedDate: return "calendar"
            case .random: return "dice"
            case .lastLogin: return "hourglass"
            }
        }
        
        var description: String {
            switch self {
            case .fixedDate: return "指定した日時に届く"
            case .random: return "期間内のランダムな日時に届く"
            case .lastLogin: return "あなたがアプリを開かなかったら届く"
            }
        }
    }
    
    enum DateMode: String, CaseIterable, Identifiable {
        case fixed = "固定"
        case random = "ランダム"
        var id: String { rawValue }
    }
    
    enum TimeMode: String, CaseIterable, Identifiable {
        case fixed = "固定"
        case random = "ランダム"
        var id: String { rawValue }
    }
    
    // MARK: - Initializer
    
    init(preselectedFriend: PairingService.Friend? = nil) {
        _selectedFriend = State(initialValue: preselectedFriend)
        
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let threeMonthsLater = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        let calendar = Calendar.current
        
        _fixedDate = State(initialValue: tomorrow)
        _fixedTime = State(initialValue: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date())
        _randomStartDate = State(initialValue: tomorrow)
        _randomEndDate = State(initialValue: threeMonthsLater)
        _startTime = State(initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
        _endTime = State(initialValue: calendar.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date())
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                recipientSection
                contentSection
                photoSection
                deliveryConditionSection
                
                if deliveryCondition != .lastLogin {
                    deliveryDateSection
                    deliveryTimeSection
                } else {
                    lastLoginSection
                }
            }
            .navigationTitle("手紙を書く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送る") {
                        showSendConfirmation = true
                    }
                    .disabled(!canSend)
                }
            }
            .sheet(isPresented: $showingFriendPicker) {
                FriendPickerView(selectedFriend: $selectedFriend)
            }
            .alert("手紙を送りますか？", isPresented: $showSendConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("送る") {
                    sendLetter()
                }
            } message: {
                Text(sendConfirmationMessage)
            }
            .onChange(of: selectedItems) { _, newItems in
                loadPhotos(from: newItems)
            }
            .overlay {
                if isSending {
                    ProgressView("送信中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
        }
    }
    
    private var canSend: Bool {
        selectedFriend != nil && !content.isEmpty
    }
    
    // MARK: - Sections
    
    private var recipientSection: some View {
        Section {
            Button(action: { showingFriendPicker = true }) {
                HStack {
                    if let friend = selectedFriend {
                        Text(friend.friendEmoji)
                            .font(.title)
                        Text(friend.friendName)
                            .foregroundColor(.primary)
                    } else {
                        Image(systemName: "person.fill.questionmark")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("宛先を選択")
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("✉️ 宛先")
        }
    }
    
    private var contentSection: some View {
        Section {
            TextEditor(text: $content)
                .frame(minHeight: 200)
        } header: {
            Text("✏️ 手紙の内容")
        } footer: {
            Text("大切な人へのメッセージを書きましょう")
        }
    }
    
    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 5, matching: .images) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(selectedImages.isEmpty ? "写真を追加（最大5枚）" : "\(selectedImages.count)枚選択中")
                }
            }
            
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                Button(action: { selectedImages.remove(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                }
                .frame(height: 90)
            }
        } header: {
            Text("📷 写真")
        }
    }
    
    private var deliveryConditionSection: some View {
        Section {
            Picker("配信条件", selection: $deliveryCondition) {
                ForEach(DeliveryCondition.allCases) { condition in
                    Label(condition.rawValue, systemImage: condition.icon)
                        .tag(condition)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("📬 配信条件")
        } footer: {
            Text(deliveryCondition.description)
        }
    }
    
    private var deliveryDateSection: some View {
        Section {
            if deliveryCondition == .fixedDate {
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
            if deliveryCondition == .random && !useDateRange {
                Text("💡 期間を指定しない場合、1日後〜3年後の間でサプライズ配達されます")
            }
        }
    }
    
    private var deliveryTimeSection: some View {
        Section {
            Picker("時間", selection: $timeMode) {
                ForEach(TimeMode.allCases) { mode in
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
            if timeMode == .random && !useTimeRange {
                Text("💡 時間帯を指定しない場合、終日いつでも届く可能性があります")
            }
        }
    }
    
    private var lastLoginSection: some View {
        Section {
            Picker("期間", selection: $lastLoginDays) {
                Text("7日間").tag(7)
                Text("14日間").tag(14)
                Text("30日間").tag(30)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("⏳ 最終ログインからの日数")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("あなたが\(lastLoginDays)日間アプリを開かなかった場合、この手紙が送信されます。")
                Text("⚠️ 送信前にプッシュ通知でお知らせします。ログインすればキャンセルできます。")
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Confirmation Message
    
    private var sendConfirmationMessage: String {
        guard let friend = selectedFriend else { return "" }
        
        var lines: [String] = []
        lines.append("宛先: \(friend.friendEmoji) \(friend.friendName)")
        lines.append("")
        
        switch deliveryCondition {
        case .fixedDate:
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateFormat = "M月d日"
            let dateText = dateFormatter.string(from: fixedDeliveryDay)
            
            if timeMode == .fixed {
                let timeFormatter = DateFormatter()
                timeFormatter.locale = Locale(identifier: "ja_JP")
                timeFormatter.dateFormat = "H:mm"
                lines.append("📅 \(dateText) \(timeFormatter.string(from: fixedTime)) に届きます")
            } else if useTimeRange {
                let timeFormatter = DateFormatter()
                timeFormatter.locale = Locale(identifier: "ja_JP")
                timeFormatter.dateFormat = "H:mm"
                lines.append("📅 \(dateText) の \(timeFormatter.string(from: startTime))〜\(timeFormatter.string(from: endTime)) のどこかに届きます")
            } else {
                lines.append("📅 \(dateText) のどこかの時間に届きます")
            }
            
        case .random:
            var deliveryDescription: String
            if useDateRange {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "M/d"
                deliveryDescription = "\(dateFormatter.string(from: randomStartDate))〜\(dateFormatter.string(from: randomEndDate))"
            } else {
                deliveryDescription = "いつか（1日後〜3年後）"
            }
            
            if timeMode == .fixed {
                let timeFormatter = DateFormatter()
                timeFormatter.locale = Locale(identifier: "ja_JP")
                timeFormatter.dateFormat = "H:mm"
                lines.append("🎲 \(deliveryDescription) の \(timeFormatter.string(from: fixedTime)) ごろに届きます")
            } else if useTimeRange {
                let timeFormatter = DateFormatter()
                timeFormatter.locale = Locale(identifier: "ja_JP")
                timeFormatter.dateFormat = "H:mm"
                lines.append("🎲 \(deliveryDescription) の \(timeFormatter.string(from: startTime))〜\(timeFormatter.string(from: endTime)) のどこかに届きます")
            } else {
                lines.append("🎲 \(deliveryDescription) に届きます")
            }
            
        case .lastLogin:
            lines.append("⏳ あなたが\(lastLoginDays)日間ログインしなかった場合に届きます")
            lines.append("")
            lines.append("大切な人へのメッセージとして送信されます")
        }
        
        lines.append("")
        lines.append("E2EE暗号化で安全に送信されます 🔒")
        
        return lines.joined(separator: "\n")
    }
    
    private var combinedDeliveryDate: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: fixedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: fixedTime)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return calendar.date(from: components) ?? fixedDate
    }
    
    private var fixedDeliveryDay: Date {
        Calendar.current.startOfDay(for: fixedDate)
    }
    
    private var requiresScheduledDeliveryDate: Bool {
        switch deliveryCondition {
        case .fixedDate:
            return timeMode == .random
        case .random:
            return true
        case .lastLogin:
            return false
        }
    }
    
    // MARK: - Photo Loading
    
    private func loadPhotos(from items: [PhotosPickerItem]) {
        selectedImages = []
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        if selectedImages.count < 5 {
                            selectedImages.append(image)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Send Letter
    
    private func sendLetter() {
        guard let friend = selectedFriend else { return }
        
        isSending = true
        
        _Concurrency.Task {
            do {
                // 配信条件を変換
                let condition: LetterSendingService.DeliveryCondition
                switch deliveryCondition {
                case .fixedDate:
                    condition = .fixedDate
                case .random:
                    condition = .random
                case .lastLogin:
                    condition = .lastLogin
                }
                
                // 配信日時を計算
                var deliveryDateParam: Date? = nil
                var randomStartParam: Date? = nil
                var randomEndParam: Date? = nil
                var scheduledDeliveryDateParam: Date? = nil
                var lastLoginDaysParam: Int? = nil
                var initialStatus: LetterSendingService.EncryptedLetter.LetterStatus = .pending
                
                switch deliveryCondition {
                case .fixedDate:
                    if timeMode == .fixed {
                        deliveryDateParam = combinedDeliveryDate
                    } else {
                        deliveryDateParam = fixedDeliveryDay
                    }
                    
                case .random:
                    if useDateRange {
                        randomStartParam = randomStartDate
                        randomEndParam = randomEndDate
                    }
                    
                case .lastLogin:
                    lastLoginDaysParam = lastLoginDays
                }
                
                if requiresScheduledDeliveryDate {
                    scheduledDeliveryDateParam = generateScheduledDeliveryDate()
                    initialStatus = .scheduled
                }
                
                // E2EE暗号化して送信
                try await LetterSendingService.shared.sendLetter(
                    content: content,
                    photos: selectedImages,
                    recipient: friend,
                    deliveryCondition: condition,
                    deliveryDate: deliveryDateParam,
                    randomStartDate: randomStartParam,
                    randomEndDate: randomEndParam,
                    scheduledDeliveryDate: scheduledDeliveryDateParam,
                    lastLoginDays: lastLoginDaysParam,
                    initialStatus: initialStatus
                )
                
                await MainActor.run {
                    isSending = false
                    HapticManager.success()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func generateScheduledDeliveryDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let deliveryDay: Date
        
        switch deliveryCondition {
        case .fixedDate:
            deliveryDay = fixedDeliveryDay
            
        case .random:
            if useDateRange {
                let start = Calendar.current.startOfDay(for: randomStartDate)
                let end = Calendar.current.startOfDay(for: randomEndDate)
                let dayRange = calendar.dateComponents([.day], from: start, to: end).day ?? 1
                let randomDays = Int.random(in: 0...max(0, dayRange))
                deliveryDay = calendar.date(byAdding: .day, value: randomDays, to: start) ?? start
            } else {
                let rangeStart = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                let rangeEnd = calendar.date(byAdding: .year, value: 3, to: now) ?? now
                let dayRange = calendar.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 1
                let randomDays = Int.random(in: 0...max(0, dayRange))
                deliveryDay = calendar.date(byAdding: .day, value: randomDays, to: rangeStart) ?? rangeStart
            }
            
        case .lastLogin:
            return now
        }
        
        let hour: Int
        let minute: Int
        
        if timeMode == .fixed {
            let components = calendar.dateComponents([.hour, .minute], from: fixedTime)
            hour = components.hour ?? 12
            minute = components.minute ?? 0
        } else if useTimeRange {
            let startTotalMinutes = calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
            let endTotalMinutes = calendar.component(.hour, from: endTime) * 60 + calendar.component(.minute, from: endTime)
            let upperBound = max(startTotalMinutes + 1, endTotalMinutes)
            let randomTotalMinutes = Int.random(in: startTotalMinutes..<upperBound)
            hour = randomTotalMinutes / 60
            minute = randomTotalMinutes % 60
        } else {
            hour = Int.random(in: 0...23)
            minute = Int.random(in: 0...59)
        }
        
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: deliveryDay) ?? deliveryDay
    }
}

// MARK: - Friend Picker View

struct FriendPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pairingService = PairingService.shared
    @Binding var selectedFriend: PairingService.Friend?
    
    var body: some View {
        NavigationStack {
            Group {
                if pairingService.friends.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("友達がいません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("まず友達を招待してください")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(pairingService.friends) { friend in
                            Button(action: {
                                selectedFriend = friend
                                dismiss()
                            }) {
                                HStack(spacing: 12) {
                                    Text(friend.friendEmoji)
                                        .font(.largeTitle)
                                    
                                    Text(friend.friendName)
                                        .font(.headline)
                                    
                                    Spacer()
                                    
                                    if selectedFriend?.id == friend.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("宛先を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                pairingService.startListeningToFriends()
            }
        }
    }
}

#Preview {
    SharedLetterEditorView()
}
