//
//  DevPCLLMService.swift
//  lifelog
//
//  開発者のPC（Mac Mini）で動作するLLMにリクエストを送るサービス
//  おお！贅沢！開発者の電気代！
//

import Foundation
import FirebaseFirestore
import Combine

/// 開発者PC LLMサービス
/// Cloudflare Tunnel経由でOllama APIにアクセス
@MainActor
class DevPCLLMService: ObservableObject {
    static let shared = DevPCLLMService()
    
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var responseText = ""
    @Published var thinkingText = "" // <think>タグ内のテキスト
    @Published var errorMessage: String?
    @Published var globalUsageCount: Int = 0
    
    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private let userDefaultsKey = "devpc_llm_usage"
    private var streamTask: _Concurrency.Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    /// サービスが利用可能かどうか（設定ファイルにURLが設定されているか）
    var isAvailable: Bool {
        !LLMConfig.tunnelURL.isEmpty && LLMConfig.tunnelURL != "https://xxx.trycloudflare.com"
    }
    
    /// 今週の残り利用回数
    var remainingUsesThisWeek: Int {
        max(0, LLMConfig.weeklyLimit - usageThisWeek)
    }
    
    /// 今週使えるかどうか
    var canUseThisWeek: Bool {
        remainingUsesThisWeek > 0
    }
    
    // MARK: - Rate Limiting
    
    private var usageThisWeek: Int {
        let data = loadUsageData()
        if isCurrentWeek(data.weekStart) {
            return data.count
        }
        return 0
    }
    
    private struct UsageData: Codable {
        var weekStart: Date
        var count: Int
    }
    
    private func loadUsageData() -> UsageData {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let usage = try? JSONDecoder().decode(UsageData.self, from: data) else {
            return UsageData(weekStart: startOfCurrentWeek(), count: 0)
        }
        return usage
    }
    
    private func saveUsageData(_ usage: UsageData) {
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    private func incrementUsage() {
        var usage = loadUsageData()
        if isCurrentWeek(usage.weekStart) {
            usage.count += 1
        } else {
            // 新しい週なのでリセット
            usage = UsageData(weekStart: startOfCurrentWeek(), count: 1)
        }
        saveUsageData(usage)
    }
    
    private func isCurrentWeek(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    private func startOfCurrentWeek() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return calendar.date(from: components) ?? Date()
    }
    
    // MARK: - Global Counter
    
    /// グローバル使用回数を取得
    func fetchGlobalUsage() async {
        do {
            let doc = try await db.collection("stats").document("llm_usage").getDocument()
            if let data = doc.data(), let count = data["totalRequests"] as? Int {
                globalUsageCount = count
            }
        } catch {
            print("⚠️ グローバルカウンター取得失敗: \(error)")
        }
    }
    
    /// グローバル使用回数をインクリメント
    private func incrementGlobalUsage() async {
        do {
            try await db.collection("stats").document("llm_usage").setData([
                "totalRequests": FieldValue.increment(Int64(1))
            ], merge: true)
            globalUsageCount += 1
        } catch {
            print("⚠️ グローバルカウンター更新失敗: \(error)")
        }
    }
    
    // MARK: - API Request
    
    /// LLMにプロンプトを送信（ストリーミング）
    func ask(prompt: String) async {
        guard canUseThisWeek else {
            errorMessage = "週3回！限界！また来週！"
            return
        }
        
        guard isAvailable else {
            errorMessage = "設定が見つかりません"
            return
        }
        
        // 状態リセット
        isLoading = true
        responseText = ""
        thinkingText = ""
        errorMessage = nil
        
        // 使用回数は成功時のみカウント（performStreamingRequest内で）
        
        // ストリーミングリクエスト
        streamTask = _Concurrency.Task {
            await performStreamingRequest(prompt: prompt)
        }
    }
    
    /// リクエストをキャンセル
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isLoading = false
    }
    
    private func performStreamingRequest(prompt: String) async {
        let urlString = "\(LLMConfig.tunnelURL)/api/generate"
        guard let url = URL(string: urlString) else {
            errorMessage = "URLが不正です"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = LLMConfig.timeoutSeconds
        
        let body: [String: Any] = [
            "model": LLMConfig.modelName,
            "prompt": prompt,
            "stream": true
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            errorMessage = "リクエスト作成失敗"
            isLoading = false
            return
        }
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "開発者のPC！寝てる！"
                isLoading = false
                return
            }
            
            var isInsideThinkTag = false
            var currentThinkContent = ""

            
            for try await line in bytes.lines {
                if _Concurrency.Task.isCancelled { break }
                
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                
                // DeepSeek-R1形式: "thinking" フィールドに思考過程が入る
                // 差分が送られてくるので、単純に追加する
                if let thinkingContent = json["thinking"] as? String, !thinkingContent.isEmpty {
                    thinkingText += thinkingContent
                }
                
                // 通常の回答
                if let responseContent = json["response"] as? String {
                    // <think>タグの処理（他のモデル用のフォールバック）
                    var text = responseContent
                    
                    // <think>タグの開始を検出
                    if text.contains("<think>") {
                        isInsideThinkTag = true
                        text = text.replacingOccurrences(of: "<think>", with: "")
                    }
                    
                    // </think>タグの終了を検出
                    if text.contains("</think>") {
                        isInsideThinkTag = false
                        let parts = text.components(separatedBy: "</think>")
                        if parts.count > 0 {
                            currentThinkContent += parts[0]
                            if thinkingText.isEmpty {
                                thinkingText = currentThinkContent
                            }
                        }
                        if parts.count > 1 {
                            self.responseText += parts[1]
                        }
                        continue
                    }
                    
                    if isInsideThinkTag {
                        currentThinkContent += text
                        if thinkingText.isEmpty || !currentThinkContent.isEmpty {
                            thinkingText = currentThinkContent
                        }
                    } else {
                        self.responseText += text
                    }
                }
                
                // 完了チェック
                if let done = json["done"] as? Bool, done {
                    break
                }
            }
            
            // 成功時のみ使用回数をカウント
            incrementUsage()
            await incrementGlobalUsage()
            
            isLoading = false
            
        } catch is CancellationError {
            isLoading = false
        } catch {
            let nsError = error as NSError
            print("❌ LLM Error: \(error)")
            print("❌ Error Domain: \(nsError.domain)")
            print("❌ Error Code: \(nsError.code)")
            print("❌ URL: \(urlString)")
            
            if nsError.code == NSURLErrorTimedOut {
                errorMessage = "開発者のPC！遅い！タイムアウト！"
            } else if nsError.code == NSURLErrorCannotConnectToHost ||
                      nsError.code == NSURLErrorCannotFindHost {
                errorMessage = "開発者のPC！寝てる！(\(nsError.code))"
            } else if nsError.code == NSURLErrorNotConnectedToInternet {
                errorMessage = "インターネット接続なし！"
            } else {
                errorMessage = "エラー: \(error.localizedDescription) (code: \(nsError.code))"
            }
            isLoading = false
        }
    }
}
