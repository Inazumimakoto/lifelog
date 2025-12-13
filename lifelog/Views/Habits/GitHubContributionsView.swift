//
//  GitHubContributionsView.swift
//  lifelog
//
//  GitHub Contributions グラフ表示
//

import SwiftUI

struct GitHubContributionsView: View {
    @StateObject private var githubService = GitHubService.shared
    @AppStorage("githubUsername") private var githubUsername: String = ""
    
    private let columns = 53 // 1年間の週数
    private let rows = 7    // 曜日数
    
    var body: some View {
        VStack(spacing: 16) {
            contributionGraphSection
            statsSection
        }
    }
    
    // MARK: - Contribution Graph
    
    private var contributionGraphSection: some View {
        SectionCard(title: "GitHub Contributions") {
            VStack(alignment: .leading, spacing: 12) {
                if githubService.isLoading {
                    HStack {
                        ProgressView()
                        Text("読み込み中...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                } else if let error = githubService.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                } else if githubService.contributions.isEmpty {
                    Text("コントリビューションデータがありません")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    contributionGrid
                    
                    HStack {
                        Text("Less")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        ForEach(0..<5) { level in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForLevel(level))
                                .frame(width: 10, height: 10)
                        }
                        
                        Text("More")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var contributionGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(0..<columns, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<rows, id: \.self) { day in
                            let contribution = getContribution(week: week, day: day)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForLevel(contribution?.level ?? 0))
                                .frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }
    }
    
    private func getContribution(week: Int, day: Int) -> GitHubContribution? {
        let calendar = Calendar.current
        
        // 今年の最初の週の日曜日を取得
        guard let yearStart = calendar.date(from: DateComponents(year: calendar.component(.year, from: Date()), month: 1, day: 1)) else {
            return nil
        }
        
        // 年の最初の週の日曜日を計算
        let weekday = calendar.component(.weekday, from: yearStart)
        guard let firstSunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: yearStart) else {
            return nil
        }
        
        // week と day から日付を計算
        guard let targetDate = calendar.date(byAdding: .day, value: week * 7 + day, to: firstSunday) else {
            return nil
        }
        
        // 該当日のコントリビューションを検索
        return githubService.contributions.first { calendar.isDate($0.date, inSameDayAs: targetDate) }
    }
    
    private func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 0: return Color(.systemGray6)
        case 1: return Color(red: 0.6, green: 0.85, blue: 0.6)
        case 2: return Color(red: 0.4, green: 0.75, blue: 0.4)
        case 3: return Color(red: 0.2, green: 0.65, blue: 0.2)
        case 4: return Color(red: 0.1, green: 0.5, blue: 0.1)
        default: return Color(.systemGray6)
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        SectionCard(title: "統計") {
            VStack(spacing: 12) {
                HStack {
                    statItem(title: "今日", value: "\(githubService.todayContributions)", icon: "calendar.day.timeline.leading")
                    Divider()
                    statItem(title: "今週", value: "\(githubService.thisWeekContributions)", icon: "calendar")
                    Divider()
                    statItem(title: "今月", value: "\(githubService.thisMonthContributions)", icon: "calendar.badge.clock")
                }
                
                Divider()
                
                HStack {
                    statItem(title: "過去1年", value: "\(githubService.totalContributions)", icon: "flame.fill")
                    Divider()
                    statItem(title: "連続日数", value: "\(githubService.currentStreak)日", icon: "bolt.fill")
                }
            }
        }
    }
    
    private func statItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    GitHubContributionsView()
}
