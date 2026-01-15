//
//  AnalysisExportView.swift
//  lifelog
//
//  Created by Codex on 2025/12/04.
//

import SwiftUI
import UIKit

struct AnalysisExportView: View {
    @Environment(\.dismiss) var dismiss
    
    // データソース
    let store: AppDataStore
    
    // 状態管理
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var selectedPersona: AI_Persona = .counselor
    
    // データトグル
    @State private var includeDiary: Bool = true
    @State private var includeSleep: Bool = true
    @State private var includeSteps: Bool = true
    @State private var includeMood: Bool = true
    @State private var includeEvents: Bool = true
    @State private var includeHabits: Bool = true
    @State private var includeGitHub: Bool = false
    
    // GitHub設定
    @AppStorage("githubUsername") private var githubUsername: String = ""
    @StateObject private var githubService = GitHubService.shared
    
    private var isGitHubEnabled: Bool {
        !githubUsername.isEmpty
    }
    
    // AIアプリ選択シート用
    @State private var showAIAppSelectionSheet = false
    @State private var selectedAIProvider: AIProvider = .chatgpt
    
    // 期間内のデータをフィルタリング
    private var targetDays: [DailyData] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        var days: [DailyData] = []
        var currentDate = start
        
        while currentDate <= end {
            let diary = store.diaryEntries.first { calendar.isDate($0.date, inSameDayAs: currentDate) }
            let health = store.healthSummaries.first { calendar.isDate($0.date, inSameDayAs: currentDate) }
            let events = store.events(on: currentDate)
            let dayTasks = store.tasks.filter { task in
                if let startDate = task.startDate {
                    return calendar.isDate(startDate, inSameDayAs: currentDate)
                }
                return false
            }
            let habitRecordsForDay = store.habitRecords.filter { calendar.isDate($0.date, inSameDayAs: currentDate) }
            let totalHabits = store.habits.count
            let completedHabits = habitRecordsForDay.filter { $0.isCompleted }.count
            // GitHubコミット数を取得
            var githubCommits = 0
            if includeGitHub {
                githubCommits = githubService.contributions
                    .first { calendar.isDate($0.date, inSameDayAs: currentDate) }?.count ?? 0
            }
            
            days.append(DailyData(
                date: currentDate,
                diary: diary,
                healthSummary: health,
                eventCount: events.count,
                taskCount: dayTasks.count,
                completedTasks: dayTasks.filter { $0.isCompleted }.count,
                totalHabits: totalHabits,
                completedHabits: completedHabits,
                githubCommits: githubCommits
            ))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
        }
        
        return days
    }
    
    // 生成テキスト
    private var generatedText: String {
        PromptGenerator.build(
            persona: selectedPersona,
            days: targetDays,
            includeDiary: includeDiary,
            includeSleep: includeSleep,
            includeSteps: includeSteps,
            includeMood: includeMood,
            includeEvents: includeEvents,
            includeHabits: includeHabits,
            includeGitHub: includeGitHub
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                // 0. 機能説明
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("この機能について")
                            .font(.headline)
                        Text("このアプリが分析するわけではありません。\nChatGPTやClaudeなどのAIに貼り付けるための「データ + 指示文」を書き出す機能です。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 1. 期間選択
                Section(header: Text("分析期間")) {
                    DatePicker("開始", selection: $startDate, displayedComponents: .date)
                    DatePicker("終了", selection: $endDate, displayedComponents: .date)
                    Text("対象データ: \(targetDays.count)日分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // 2. ペルソナ選択
                Section(header: Text("AIの人格")) {
                    Picker("担当者", selection: $selectedPersona) {
                        ForEach(AI_Persona.allCases) { persona in
                            HStack {
                                Image(systemName: persona.icon)
                                Text(persona.rawValue)
                            }
                            .tag(persona)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    
                    // キャラクターの説明文を表示
                    Text(selectedPersona.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
                
                // 3. データ項目の選択
                Section(header: Text("含めるデータ")) {
                    Toggle("📝 日記本文", isOn: $includeDiary)
                    Toggle("😊 気分・体調", isOn: $includeMood)
                    Toggle("💤 睡眠時間", isOn: $includeSleep)
                    Toggle("👣 歩数", isOn: $includeSteps)
                    Toggle("📅 予定・タスク数", isOn: $includeEvents)
                    Toggle("✅ 習慣達成率", isOn: $includeHabits)
                    
                    // GitHubが有効な場合のみ表示
                    if isGitHubEnabled {
                        Toggle("💻 GitHubコミット", isOn: $includeGitHub)
                    }
                }
                
                Section {
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("クリップボードにコピー")
                            Spacer()
                            Text("推奨")
                                .font(.caption)
                                .padding(4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    // ShareLink を使用（iOS 16+、シート競合を回避）
                    ShareLink(
                        item: generatedText,
                        subject: Text("Lifelog AI分析データ"),
                        message: Text("ライフログのAI分析用データです")
                    ) {
                        Label("ファイルとして書き出し", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("⚠️ プライバシー保護のため、ChatGPT等のAIで使用する際は「一時チャット（履歴OFF）」または「新しいチャット」での利用を推奨します。")
                        
                        Text("📋 クリップボード警告: 期間が長いと、コピーに時間がかかったり、アプリの動作が重くなる場合があります。")
                        
                        Text("🧠 AI容量警告: 文章が極端に長くなると、AIが最初の方の内容を忘れてしまったり、読み込めないことがあります。まずは1〜2か月分くらいから試すのがおすすめです。")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
                
                // 開発者のPC セクション
                if DevPCLLMService.shared.isAvailable {
                    Section {
                        Button {
                            askDevPC()
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text("直接分析")
                                Spacer()
                                Text("残\(DevPCLLMService.shared.remainingUsesThisWeek)回")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        DevPCLLMService.shared.canUseThisWeek ? Color.green.opacity(0.2) : Color.red.opacity(0.2),
                                        in: Capsule()
                                    )
                            }
                        }
                        .disabled(!DevPCLLMService.shared.canUseThisWeek)
                    } header: {
                        Text("直接分析")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("データはどこにも保存されません")
                            Text("ソースコードはGitHubで公開中")
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("AI分析用データ書き出し")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showAIAppSelectionSheet) {
                AIAppSelectionSheet()
            }
            .sheet(isPresented: $showAIAppSelectionSheet) {
                AIAppSelectionSheet()
            }
            .sheet(isPresented: $showDevPCSheet, onDismiss: {
                devPCPrompt = ""  // リセット
            }) {
                Group {
                    if !devPCPrompt.isEmpty {
                        DevPCResponseView(prompt: devPCPrompt)
                    } else {
                        Color.clear
                    }
                }
            }
        }
        // 初期化時の期間設定（今月の1日から今日まで）
        .onAppear {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: Date())
            startDate = calendar.date(from: components) ?? Date()
            
            // GitHubデータをフェッチ
            if isGitHubEnabled {
                _Concurrency.Task {
                    await githubService.fetchContributions(username: githubUsername)
                }
            }
        }
        // 開発者PCへの質問プロンプト監視
        .onChange(of: devPCPrompt) { _, newValue in
            if !newValue.isEmpty {
                showDevPCSheet = true
            }
        }
        // 鬼コーチ選択時に、日記をデフォルトOFFにする
        .onChange(of: selectedPersona) { _, newPersona in
            if newPersona == .coach {
                includeDiary = false
            }
        }
    }
    
    // MARK: - State for Dev PC
    @State private var showDevPCSheet = false
    @State private var devPCPrompt = ""
    
    // MARK: - Actions
    
    private func copyToClipboard() {
        UIPasteboard.general.string = generatedText
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        showAIAppSelectionSheet = true
    }
    
    private func askDevPC() {
        devPCPrompt = generatedText
        HapticManager.light()
        // showDevPCSheet は onChange で設定される
    }
}

