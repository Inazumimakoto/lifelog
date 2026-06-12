//
//  AppLogger.swift
//  lifelog
//

import Foundation
import os

/// アプリ共通のロガー。bare print はリリースビルドでもデバイスログに
/// 平文で残るため、os.Logger に寄せる。文字列補間のうちリテラル以外は
/// リリースでは既定で <private> に伏せられる（プライバシー対策の本体）。
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "lifelog"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let letters = Logger(subsystem: subsystem, category: "letters")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let health = Logger(subsystem: subsystem, category: "health")
    static let widgets = Logger(subsystem: subsystem, category: "widgets")
    static let general = Logger(subsystem: subsystem, category: "general")
}
