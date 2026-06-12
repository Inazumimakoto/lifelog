//
//  Persistence.swift
//  lifelog
//
//  Created for SwiftData Migration
//

import Foundation
import SwiftData
import os

// ウィジェット拡張ターゲットとファイルを共有するため、AppLogger は使用せず
// ファイルローカルのロガーを定義する
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lifelog", category: "data")

struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    // App Group IDs (must be present in app/widget entitlements)
    private static let defaultAppGroupIdentifier = "group.lifelog.share"
    private static let screenshotsAppGroupIdentifier = "group.lifelog.screenshots"
    private static let activeAppGroupDefaultsKey = "lifelog.activeAppGroupIdentifier"
    private static let screenshotsLaunchArguments: Set<String> = [
        "-screenshots-mode",
        "-ScreenshotsMode",
    ]

    private static var isRunningInExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex" ||
        Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil
    }

    private static var isScreenshotsModeLaunch: Bool {
        let arguments = Set(ProcessInfo.processInfo.arguments)
        return screenshotsLaunchArguments.isDisjoint(with: arguments) == false
    }

    /// Active App Group used by app + widgets.
    ///
    /// - App launch:
    ///   - `-screenshots-mode` -> screenshots group
    ///   - default -> normal group
    /// - Widget extension:
    ///   - follows the latest app selection stored in shared defaults.
    static var appGroupIdentifier: String {
        let selected: String
        if isScreenshotsModeLaunch {
            selected = screenshotsAppGroupIdentifier
        } else if isRunningInExtension {
            selected = persistedActiveAppGroupIdentifier ?? defaultAppGroupIdentifier
        } else {
            selected = defaultAppGroupIdentifier
        }

        persistActiveAppGroupIdentifierIfNeeded(selected)
        return selected
    }

    private static var persistedActiveAppGroupIdentifier: String? {
        guard let defaults = UserDefaults(suiteName: defaultAppGroupIdentifier) else { return nil }
        guard let value = defaults.string(forKey: activeAppGroupDefaultsKey) else { return nil }
        let allowed = [defaultAppGroupIdentifier, screenshotsAppGroupIdentifier]
        return allowed.contains(value) ? value : nil
    }

    private static func persistActiveAppGroupIdentifierIfNeeded(_ identifier: String) {
        guard isRunningInExtension == false else { return }
        guard let defaults = UserDefaults(suiteName: defaultAppGroupIdentifier) else { return }
        defaults.set(identifier, forKey: activeAppGroupDefaultsKey)
    }

    init(inMemory: Bool = false) {
        let schema = Schema([
            SDTask.self,
            SDDiaryEntry.self,
            SDHabit.self,
            SDHabitRecord.self,
            SDAnniversary.self,
            SDHealthSummary.self,
            SDCalendarEvent.self,
            SDMemoPad.self,
            SDAppState.self,
            SDLetter.self,
            SDSharedLetter.self
        ])
        
        if inMemory {
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create in-memory ModelContainer: \(error)")
            }
            return
        }
        
        let storeURL = Self.resolveStoreURL()
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL
            // CloudKit同期は追加設定が必要 - 後日対応
        )

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // ここで落とすとアプリもウィジェットも起動不能ループに陥る。
            // 破損ストアは「削除せず」退避して新しいストアで起動を続ける。
            // 退避はアプリ本体のプロセスに限る: ウィジェット拡張が
            // アプリの開いているストアファイルを動かすと二次破損しうる。
            if Self.isRunningInExtension {
                fatalError("Could not create ModelContainer (extension): \(error)")
            }
            logger.error("ModelContainer creation failed, quarantining store: \(error)")
            Self.quarantineStore(at: storeURL)
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                UserDefaults(suiteName: Self.appGroupIdentifier)?
                    .set(true, forKey: Self.storeRecoveryOccurredKey)
            } catch {
                // 新規ストアすら作れないのはディスク満杯等の環境異常で、
                // この先どの書き込みも成功しない。ここは落とすのが誠実。
                fatalError("Could not create ModelContainer after store recovery: \(error)")
            }
        }
    }

    /// 破損ストアを退避して新規作成したことを示すフラグ(App Group defaults)。
    /// アプリ起動時に読み取り、ユーザーへ通知してからクリアする。
    static let storeRecoveryOccurredKey = "lifelog.storeRecoveryOccurred"

    /// App Group 内のストアURLを決定し、必要なら Sandbox からの移行を行う
    private static func resolveStoreURL() -> URL {
        let fileManager = FileManager.default
        let sandboxURL = URL.applicationSupportDirectory.appendingPathComponent("default.store")

        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            logger.error("WARNING: App Group container not found. Falling back to default location.")
            return sandboxURL
        }
        let storeURL = groupURL.appendingPathComponent("default.store")

        // App Group 側にまだストアがなく Sandbox 側にある場合のみ移行する
        if !fileManager.fileExists(atPath: storeURL.path) && fileManager.fileExists(atPath: sandboxURL.path) {
            do {
                try migrateStoreFiles(from: sandboxURL, to: storeURL)
                logger.info("Successfully moved SwiftData store to App Group.")
            } catch {
                // 移行に失敗したらこの起動は旧ストアをそのまま使う(データ優先)。
                // 移行は次回起動時に再試行される。
                logger.error("Failed to move SwiftData store, using sandbox store this launch: \(error)")
                return sandboxURL
            }
        }
        return storeURL
    }

    /// Sandbox → App Group のストア移行。
    /// 旧実装は move を3回逐次実行しており、途中で kill されると WAL が
    /// 取り残されて直近の書き込みが消える恐れがあった(さらに aux ファイル名を
    /// "default.store.shm" と誤っており実際には移せていなかった。正しくは
    /// "default.store-shm")。コピー→本体を最後に配置→元を削除の順にし、
    /// どの時点で中断しても次回起動でやり直せるようにする
    /// (App Group 側 .store の存在が移行完了の印になるため本体は最後)。
    private static func migrateStoreFiles(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let auxSuffixes = ["-shm", "-wal"]

        // 前回の移行が途中で死んだ場合の残骸を掃除してからコピーする
        for suffix in auxSuffixes {
            let dest = URL(fileURLWithPath: destination.path + suffix)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
        }
        for suffix in auxSuffixes {
            let src = URL(fileURLWithPath: source.path + suffix)
            let dest = URL(fileURLWithPath: destination.path + suffix)
            if fileManager.fileExists(atPath: src.path) {
                try fileManager.copyItem(at: src, to: dest)
            }
        }
        try fileManager.copyItem(at: source, to: destination)

        // コピー完了後に元を削除。ここの失敗は無害なので無視する
        // (次回起動は App Group 側の存在チェックで移行をスキップする)
        for suffix in auxSuffixes + [""] {
            let src = URL(fileURLWithPath: source.path + suffix)
            if fileManager.fileExists(atPath: src.path) {
                try? fileManager.removeItem(at: src)
            }
        }
    }

    /// 開けなくなったストア一式をタイムスタンプ付きでリネーム退避する。
    /// ユーザーデータを物理削除しないため(手動復旧・原因調査の余地を残す)。
    private static func quarantineStore(at storeURL: URL) {
        let fileManager = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: src.path) else { continue }
            let dest = URL(fileURLWithPath: storeURL.path + suffix + ".corrupt-" + stamp)
            try? fileManager.moveItem(at: src, to: dest)
        }
    }

    // For SwiftUI Previews
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        return result
    }()
}
