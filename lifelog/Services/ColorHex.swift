//
//  ColorHex.swift
//  lifelog
//
//  アプリ本体とウィジェット拡張(LifelogWidgetsExtension)の両方に
//  コンパイルされる共有ファイル。HEX文字列からの色生成は3箇所に
//  重複していて実装が食い違っていたため、ここを唯一の正とする。
//

import SwiftUI
import UIKit

/// HEX文字列を 6桁の RRGGBB へ正規化する。
/// 3桁ショートハンドは CSS 慣習どおり各桁を2回複製して展開する
/// (#F00 → FF0000、#ABC → AABBCC)。
/// 先頭の "#" や前後の記号・空白は許容するが、桁数や16進として
/// 不正な入力は nil を返す(呼び出し側は accentColor 等へフォールバックする)。
private func normalizedHexComponents(from hex: String) -> (r: Double, g: Double, b: Double)? {
    // alphanumerics 以外(# や空白)を取り除いてから桁数で分岐する。
    let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

    let expanded: String
    switch sanitized.count {
    case 3:
        // 3桁は各桁を複製して6桁へ。x/15 と xx/255 は数学的に等価だが、
        // 6桁経路と完全に同じ計算へ寄せるため文字列展開で統一する。
        expanded = sanitized.map { "\($0)\($0)" }.joined()
    case 6:
        expanded = sanitized
    default:
        return nil
    }

    guard let value = UInt64(expanded, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    return (r, g, b)
}

extension Color {
    /// 3桁/6桁の HEX 文字列から Color を生成する。不正入力は nil。
    init?(hex: String) {
        guard let comps = normalizedHexComponents(from: hex) else { return nil }
        self.init(red: comps.r, green: comps.g, blue: comps.b)
    }
}

extension UIColor {
    /// 3桁/6桁の HEX 文字列から UIColor を生成する。不正入力は nil。
    /// 旧 ScheduleWidget の実装は6桁のみ対応で3桁を弾いていたため、
    /// 3桁HEXのカテゴリ色がウィジェットでだけ accentColor に化けていた。
    convenience init?(hex: String) {
        guard let comps = normalizedHexComponents(from: hex) else { return nil }
        self.init(red: comps.r, green: comps.g, blue: comps.b, alpha: 1.0)
    }
}
