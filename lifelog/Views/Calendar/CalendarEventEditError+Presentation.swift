import Foundation

extension CalendarEventEditError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .readOnly:
            return String(localized: "外部カレンダーの予定は編集できません。")
        case .missingEvent:
            return String(localized: "この予定は見つかりません。画面を開き直してください。")
        case .invalidScope:
            return String(localized: "この予定には選んだ変更範囲を適用できません。変更範囲を選び直してください。")
        case .recurrenceRequiresSeries:
            return String(localized: "繰り返しの設定を変更するときは、「これ以降」または「すべて」を選んでください。")
        case .invalidDates:
            return String(localized: "開始・終了日時と繰り返しの終了日を確認してください。")
        case .stalePlan:
            return String(localized: "予定が変更されました。編集内容を確認してから画面を開き直してください。")
        }
    }
}
