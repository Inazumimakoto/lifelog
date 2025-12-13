//
//  GitHubService.swift
//  lifelog
//
//  GitHub Contributions データ取得サービス
//

import Foundation
import Combine

/// GitHubコントリビューションの日別データ
struct GitHubContribution: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    
    /// コントリビューションレベル（0-4）
    var level: Int {
        switch count {
        case 0: return 0
        case 1...3: return 1
        case 4...6: return 2
        case 7...9: return 3
        default: return 4
        }
    }
}

/// GitHub Contributions サービス
/// ユーザー名からコントリビューションデータを取得
@MainActor
class GitHubService: ObservableObject {
    static let shared = GitHubService()
    
    @Published var contributions: [GitHubContribution] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var totalContributions: Int = 0
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private init() {}
    
    /// GitHubユーザー名からコントリビューションを取得
    func fetchContributions(username: String) async {
        guard !username.isEmpty else {
            contributions = []
            totalContributions = 0
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let urlString = "https://github.com/users/\(username)/contributions"
        guard let url = URL(string: urlString) else {
            errorMessage = "無効なユーザー名です"
            isLoading = false
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "ユーザーが見つかりません"
                isLoading = false
                return
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                errorMessage = "データの読み込みに失敗しました"
                isLoading = false
                return
            }
            
            parseContributions(from: html)
            isLoading = false
        } catch {
            errorMessage = "通信エラー: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    /// HTMLからコントリビューションデータをパース
    private func parseContributions(from html: String) {
        var parsedContributions: [GitHubContribution] = []
        
        // 複数のパターンを試す
        // パターン1: tool-tip タグ内のテキスト "N contributions on Date"
        // パターン2: data-date と周辺のコンテキストからコミット数を抽出
        
        // まず data-date を持つ要素とその周辺200文字を取得
        let cellPattern = #"data-date=\"(\d{4}-\d{2}-\d{2})\""#
        
        if let regex = try? NSRegularExpression(pattern: cellPattern, options: []) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, options: [], range: range)
            
            for match in matches {
                guard let dateRange = Range(match.range(at: 1), in: html) else {
                    continue
                }
                
                let dateString = String(html[dateRange])
                
                guard let date = dateFormatter.date(from: dateString) else {
                    continue
                }
                
                // マッチ位置の前後300文字を検索範囲とする
                let matchLocation = match.range.location
                let searchStart = max(0, matchLocation - 100)
                let searchEnd = min(html.count, matchLocation + 300)
                let searchRange = NSRange(location: searchStart, length: searchEnd - searchStart)
                guard let searchSwiftRange = Range(searchRange, in: html) else { continue }
                let searchString = String(html[searchSwiftRange])
                
                var count = 0
                
                // パターン1: "N contribution" または "N contributions" を探す
                // 例: "24 contributions on December 13"
                if let contributionMatch = searchString.range(of: #"(\d+)\s+contribution"#, options: .regularExpression) {
                    let matchedString = String(searchString[contributionMatch])
                    if let numberMatch = matchedString.range(of: #"\d+"#, options: .regularExpression) {
                        count = Int(matchedString[numberMatch]) ?? 0
                    }
                }
                // パターン2: "No contributions" の場合
                else if searchString.contains("No contributions") {
                    count = 0
                }
                // パターン3: data-level から推定（フォールバック）
                else if let levelMatch = searchString.range(of: #"data-level=\"(\d)\""#, options: .regularExpression) {
                    let levelString = String(searchString[levelMatch])
                    if let numberMatch = levelString.range(of: #"\d"#, options: .regularExpression),
                       let level = Int(String(levelString[numberMatch])) {
                        switch level {
                        case 0: count = 0
                        case 1: count = 1
                        case 2: count = 4
                        case 3: count = 7
                        default: count = 10
                        }
                    }
                }
                
                parsedContributions.append(GitHubContribution(date: date, count: count))
            }
        }
        
        // 日付順にソート、重複を除去（最大値を採用）
        let uniqueContributions = Dictionary(grouping: parsedContributions, by: { $0.date })
            .mapValues { contributions in
                contributions.max(by: { $0.count < $1.count })!
            }
            .values
            .sorted { $0.date < $1.date }
        
        contributions = Array(uniqueContributions)
        
        // 全データの合計を計算（過去1年分）
        totalContributions = contributions.reduce(0) { $0 + $1.count }
        
        print("🟢 GitHubパース結果: \(contributions.count)日分, 合計\(totalContributions)コミット")
    }
    
    /// 今日のコントリビューション数
    var todayContributions: Int {
        let calendar = Calendar.current
        return contributions.first { calendar.isDateInToday($0.date) }?.count ?? 0
    }
    
    /// 今週のコントリビューション数
    var thisWeekContributions: Int {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return 0
        }
        return contributions
            .filter { $0.date >= weekStart }
            .reduce(0) { $0 + $1.count }
    }
    
    /// 今月のコントリビューション数
    var thisMonthContributions: Int {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        return contributions
            .filter {
                calendar.component(.month, from: $0.date) == currentMonth &&
                calendar.component(.year, from: $0.date) == currentYear
            }
            .reduce(0) { $0 + $1.count }
    }
    
    /// 連続日数（ストリーク）
    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()
        
        // 今日からさかのぼって連続日数をカウント
        while true {
            let hasContribution = contributions.contains {
                calendar.isDate($0.date, inSameDayAs: checkDate) && $0.count > 0
            }
            
            if hasContribution {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                    break
                }
                checkDate = previousDay
            } else {
                // 今日がまだコミットなしなら昨日からカウント開始
                if streak == 0 && calendar.isDateInToday(checkDate) {
                    guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                        break
                    }
                    checkDate = yesterday
                    continue
                }
                break
            }
        }
        
        return streak
    }
}
