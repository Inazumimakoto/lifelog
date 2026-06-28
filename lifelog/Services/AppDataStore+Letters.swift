//
//  AppDataStore+Letters.swift
//  lifelog
//

import Foundation
import SwiftData
import UserNotifications
import os

extension AppDataStore {

    // MARK: - Letter to the Future

    /// ホームに表示すべき手紙を取得
    /// - 開封可能（未開封）な手紙
    /// - または、開封済みだが配達日が今日の手紙
    /// - ただし、ユーザーが非表示にした場合は除く
    func deliverableLetters() -> [Letter] {
        return letters.filter { $0.shouldShowOnHome }
    }

    /// 今日届いた手紙（今日開封した or 今日配達された未開封）
    func todaysDeliveredLetters() -> [Letter] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return letters.filter { letter in
            let deliveryDay = calendar.startOfDay(for: letter.deliveryDate)
            let isDeliveredToday = deliveryDay == today
            let isDeliverableNow = letter.status == .sealed && Date() >= letter.deliveryDate
            let openedToday = letter.status == .opened &&
                              letter.openedAt.map { calendar.startOfDay(for: $0) == today } ?? false
            return (isDeliveredToday && isDeliverableNow) || openedToday
        }
    }

    func addLetter(_ letter: Letter) {
        letters.append(letter)

        let sdLetter = SDLetter(domain: letter)
        modelContext.insert(sdLetter)
        saveContext()
    }

    func updateLetter(_ letter: Letter) {
        guard let index = letters.firstIndex(where: { $0.id == letter.id }) else { return }
        letters[index] = letter

        let letterID = letter.id
        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: letter)
            saveContext()
        }
    }

    func dismissLetterFromHome(_ letterID: UUID) {
        guard let index = letters.firstIndex(where: { $0.id == letterID }) else { return }
        letters[index].dismissFromHome()

        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: letters[index])
            saveContext()
        }
    }

    func sealLetter(_ letterID: UUID) {
        guard let index = letters.firstIndex(where: { $0.id == letterID }) else { return }
        var letter = letters[index]
        letter.seal()
        letters[index] = letter

        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: letter)
            saveContext()
        }

        // 通知をスケジュール
        scheduleLetterNotification(letter)
    }

    func openLetter(_ letterID: UUID) {
        guard let index = letters.firstIndex(where: { $0.id == letterID }) else { return }
        var letter = letters[index]
        letter.open()
        letters[index] = letter

        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: letter)
            saveContext()
        }

        // 通知をキャンセル
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["letter-\(letterID.uuidString)"])
    }

    func deleteLetter(_ letterID: UUID) {
        letters.removeAll { $0.id == letterID }

        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            saveContext()
        }

        // 通知をキャンセル
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["letter-\(letterID.uuidString)"])
    }

    private func scheduleLetterNotification(_ letter: Letter) {
        guard letter.status == .sealed else { return }

        let content = UNMutableNotificationContent()
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yMd")
        let dateString = formatter.string(from: letter.createdAt)

        content.title = String(localized: "📨 手紙が届きました")
        content.body = String(localized: "\(dateString)のあなたから手紙が届きました")
        content.sound = .default
        content.userInfo = ["letterID": letter.id.uuidString]

        let triggerDate = letter.deliveryDate
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: "letter-\(letter.id.uuidString)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notifications.error("手紙通知スケジュールエラー: \(error)")
            }
        }
    }

    // MARK: - Shared Letter (他ユーザーからの手紙)

    func addSharedLetter(_ letter: SharedLetter) {
        // 重複チェック
        guard !sharedLetters.contains(where: { $0.id == letter.id }) else {
            AppLogger.letters.debug("共有手紙は既に保存済み: \(letter.id)")
            return
        }

        sharedLetters.insert(letter, at: 0)  // 新しい順にソート

        let sdLetter = SDSharedLetter(domain: letter)
        modelContext.insert(sdLetter)
        saveContext()

        AppLogger.letters.info("共有手紙をローカルに保存: \(letter.id)")
    }

    func deleteSharedLetter(_ letterID: String) {
        sharedLetters.removeAll { $0.id == letterID }

        let descriptor = FetchDescriptor<SDSharedLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            saveContext()
        }

        // 写真も削除
        deleteSharedLetterPhotos(letterID: letterID)

        AppLogger.letters.info("共有手紙を削除: \(letterID)")
    }

    private func deleteSharedLetterPhotos(letterID: String) {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let letterDir = documentsDir.appendingPathComponent("SharedLetterPhotos/\(letterID)")
        try? FileManager.default.removeItem(at: letterDir)
    }

}
