import Foundation
import SwiftData
import SwiftUI
import UIKit
import WidgetKit
import os

#if DEBUG && targetEnvironment(simulator)
enum ASOScreenshotScreen: String {
    case reviewCalendar = "review-calendar"
    case today = "today"
    case scheduleMonth = "schedule-month"
    case reviewMap = "review-map"
    case habits = "habits"
    case countdown = "countdown"
    case health = "health"
    case diaryDetail = "diary-detail"
    case letters = "letters"
    case wallpaperLockscreen = "wallpaper-lockscreen"
    case shopping = "shopping"
    case widgetGallery = "widget-gallery"
}

enum ASOShowcaseLang {
    case ja, en, ko, zhHans, zhHant

    static var current: ASOShowcaseLang {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-aso-lang"), args.indices.contains(idx + 1) {
            return parse(args[idx + 1])
        }
        return parse(Locale.preferredLanguages.first ?? "ja")
    }

    private static func parse(_ raw: String) -> ASOShowcaseLang {
        let lower = raw.lowercased()
        if lower.hasPrefix("en") { return .en }
        if lower.hasPrefix("ko") { return .ko }
        if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh_hant") || lower.contains("tw") || lower.contains("hk") { return .zhHant }
        if lower.hasPrefix("zh") { return .zhHans }
        return .ja
    }

    var localeIdentifier: String {
        switch self {
        case .ja: return "ja_JP"
        case .en: return "en_US"
        case .ko: return "ko_KR"
        case .zhHans: return "zh_Hans_CN"
        case .zhHant: return "zh_Hant_TW"
        }
    }

    var weekdaySymbols: [String] {
        switch self {
        case .ja: return ["日", "月", "火", "水", "木", "金", "土"]
        case .en: return ["S", "M", "T", "W", "T", "F", "S"]
        case .ko: return ["일", "월", "화", "수", "목", "금", "토"]
        case .zhHans, .zhHant: return ["日", "一", "二", "三", "四", "五", "六"]
        }
    }

    func pick(_ ja: String, _ en: String, _ ko: String, _ zhHans: String, _ zhHant: String) -> String {
        switch self {
        case .ja: return ja
        case .en: return en
        case .ko: return ko
        case .zhHans: return zhHans
        case .zhHant: return zhHant
        }
    }
}

enum ASOScreenshotShowcase {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-aso-showcase")
    }

    static var requestedScreen: ASOScreenshotScreen? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-aso-screen"), args.indices.contains(idx + 1) else {
            return nil
        }
        return ASOScreenshotScreen(rawValue: args[idx + 1])
    }

    static var photoSourceDirectory: URL {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-aso-photos-dir"), args.indices.contains(idx + 1) {
            return URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/lifelify_aso/diary_photos", isDirectory: true)
    }
}

extension AppDataStore {
    /// Seeds rich, realistic showcase data in the active language exclusively for simulator ASO screenshot capture.
    func seedASOScreenshotShowcase() {
        guard ASOScreenshotShowcase.isEnabled else { return }
        let lang = ASOShowcaseLang.current
        func L(_ ja: String, _ en: String, _ ko: String, _ zhHans: String, _ zhHant: String) -> String {
            lang.pick(ja, en, ko, zhHans, zhHant)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today)!
        }

        do {
            try modelContext.delete(model: SDTask.self)
            try modelContext.delete(model: SDDiaryEntry.self)
            try modelContext.delete(model: SDHabit.self)
            try modelContext.delete(model: SDHabitRecord.self)
            try modelContext.delete(model: SDAnniversary.self)
            try modelContext.delete(model: SDHealthSummary.self)
            try modelContext.delete(model: SDCalendarEvent.self)
            try modelContext.delete(model: SDCalendarEventException.self)
            try modelContext.delete(model: SDMemoPad.self)
            try modelContext.delete(model: SDLetter.self)
            try modelContext.delete(model: SDShoppingItem.self)
            try modelContext.delete(model: SDShoppingPlace.self)
            try modelContext.save()
        } catch {
            AppLogger.data.error("ASO showcase reset failed: \(error)")
        }

        var importedPhotoPaths: [String] = []
        let sourceDir = ASOScreenshotShowcase.photoSourceDirectory
        for i in 1...27 {
            let fileURL = sourceDir.appendingPathComponent(String(format: "photo_%02d.jpg", i))
            if let data = try? Data(contentsOf: fileURL),
               let saved = try? PhotoStorage.save(data: data) {
                importedPhotoPaths.append(saved)
            }
        }
        func photo(_ index: Int) -> String? {
            guard !importedPhotoPaths.isEmpty else { return nil }
            return importedPhotoPaths[index % importedPhotoPaths.count]
        }

        let catWork = L("仕事", "Work", "업무", "工作", "工作")
        let catPersonal = L("プライベート", "Personal", "개인", "个人", "個人")
        let catHealth = L("健康", "Health", "건강", "健康", "健康")
        let catTravel = L("旅行", "Travel", "여행", "旅行", "旅行")
        let catStudy = L("学習", "Study", "학습", "学习", "學習")

        CategoryPalette.saveCategory(name: catWork, colorName: "#2563EB")
        CategoryPalette.saveCategory(name: catPersonal, colorName: "#10B981")
        CategoryPalette.saveCategory(name: catHealth, colorName: "#F59E0B")
        CategoryPalette.saveCategory(name: catTravel, colorName: "#EC4899")
        CategoryPalette.saveCategory(name: catStudy, colorName: "#8B5CF6")

        let tagCafe = L("カフェ", "Cafe", "카페", "咖啡馆", "咖啡廳")
        let tagFood = L("ご飯", "Food", "맛집", "美食", "美食")
        let tagWalk = L("運動", "Fitness", "운동", "运动", "運動")
        let tagSight = L("観光", "Sightseeing", "관광", "观光", "觀光")
        let tagFriend = L("友人", "Friends", "친구", "朋友", "朋友")
        let tagStudy = L("勉強", "Study", "공부", "学习", "學習")
        let tagWork = L("仕事", "Work", "업무", "工作", "工作")
        let tagTravel = L("旅行", "Travel", "여행", "旅行", "旅行")
        let tagShop = L("買い物", "Shopping", "쇼핑", "购物", "購物")

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let daysFromMonthStart = calendar.dateComponents([.day], from: monthStart, to: today).day ?? 26

        struct ShowcaseSpot {
            let dayOffsetFromMonthStart: Int
            let name: String
            let address: String
            let lat: Double
            let lon: Double
            let tags: [String]
            let photoIndex: Int
            let note: String
            let mood: MoodLevel
            let condition: Int
        }

        let curatedEntries: [ShowcaseSpot] = [
            ShowcaseSpot(dayOffsetFromMonthStart: 0, name: L("代官山カフェ", "Daikanyama Cafe", "다이칸야마 카페", "代官山咖啡馆", "代官山咖啡廳"), address: L("東京都渋谷区", "Shibuya, Tokyo", "도쿄 시부야", "东京涉谷", "東京澀谷"), lat: 35.6490, lon: 139.7031, tags: [tagCafe, tagFood], photoIndex: 0, note: L("朝から気持ちよく晴れた日。焼きたてのクロワッサンとラテで一日の計画を立てた。", "Sunny morning start. Planned my day over a warm croissant and latte.", "맑은 아침. 갓 구운 크루아상과 라떼로 하루 계획을 세웠다.", "晴朗的早晨，一边享用可颂和拿铁一边规划今天。", "晴朗的早晨，一邊享用可頌和拿鐵一邊規劃今天。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 1, name: L("代々木公園", "Yoyogi Park", "요요기 공원", "代代木公园", "代代木公園"), address: L("東京都渋谷区", "Shibuya, Tokyo", "도쿄 시부야", "东京涉谷", "東京澀谷"), lat: 35.6717, lon: 139.6949, tags: [tagWalk, tagSight], photoIndex: 9, note: L("並木道が木漏れ日で最高にきれいだった。朝の散歩だけで頭がすっきりする。", "Morning walk through sunlit trees cleared my mind.", "햇살이 비치는 가로수길 산책으로 머리가 맑아졌다.", "阳光洒满林荫道，晨间散步让人神清气爽。", "陽光灑滿林蔭道，晨間散步讓人神清氣爽。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 2, name: L("表参道ビストロ", "Omotesando Bistro", "오모테산도 비스트로", "表参道小酒馆", "表參道小酒館"), address: L("東京都港区", "Minato, Tokyo", "도쿄 미나토", "东京港区", "東京港區"), lat: 35.6652, lon: 139.7125, tags: [tagFood, tagFriend], photoIndex: 1, note: L("友人とランチ。トマトとバジルのパスタが絶品で、気づいたら2時間話し込んでいた。", "Great pasta lunch with a friend—talked for two hours straight.", "친구와 파스타 런치. 이야기하다 보니 어느새 두 시간이 지났다.", "和朋友吃午餐，番茄罗勒意面超赞，一聊就是两小时。", "和朋友吃午餐，番茄羅勒義麵超讚，一聊就是兩小時。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 3, name: L("清澄白河ロースタリー", "Kiyosumi Roastery", "기요스미 로스터리", "清澄白河烘焙咖啡", "清澄白河烘焙咖啡"), address: L("東京都江東区", "Koto, Tokyo", "도쿄 고토", "东京江东", "東京江東"), lat: 35.6815, lon: 139.8005, tags: [tagCafe, tagStudy], photoIndex: 2, note: L("静かな和カフェで抹茶ラテとプリン。読書の続きがすごく捗った。", "Quiet cafe afternoon with matcha latte and reading.", "조용한 카페에서 말차 라떼와 함께 독서에 집중했다.", "安静的咖啡馆里喝着抹茶拿铁看书，效率很高。", "安靜的咖啡廳裡喝著抹茶拿鐵看書，效率很高。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 4, name: L("丸の内オフィス", "Marunouchi Studio", "마루노우치 오피스", "丸之内工作室", "丸之內工作室"), address: L("東京都千代田区", "Chiyoda, Tokyo", "도쿄 지요다", "东京千代田", "東京千代田"), lat: 35.6812, lon: 139.7671, tags: [tagWork], photoIndex: 3, note: L("午前中に資料を書き終えて気持ちよくスタート。", "Finished the slide deck before noon.", "오전에 자료를 깔끔하게 마무리했다.", "上午顺利完成方案，心情轻松。", "上午順利完成方案，心情輕鬆。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 5, name: L("由比ヶ浜海岸", "Yuigahama Beach", "유이가하마 해변", "由比滨海岸", "由比濱海岸"), address: L("神奈川県鎌倉市", "Kamakura, Kanagawa", "가나가와 가마쿠라", "神奈川镰仓", "神奈川鎌倉"), lat: 35.3112, lon: 139.5416, tags: [tagTravel, tagSight], photoIndex: 10, note: L("週末の鎌倉ドライブ。穏やかな波の音を聞きながら海辺を散歩した。", "Weekend drive to Kamakura—peaceful walk by the ocean.", "주말 가마쿠라 드라이브. 잔잔한 파도 소리를 들으며 산책했다.", "周末自驾去镰仓，在海边散步听浪。", "週末自駕去鎌倉，在海邊散步聽浪。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 6, name: L("江ノ電沿線", "Enoden Coastline", "에노덴 해안길", "江之电海岸线", "江之電海岸線"), address: L("神奈川県鎌倉市", "Kamakura", "가마쿠라", "镰仓", "鎌倉"), lat: 35.3065, lon: 139.5103, tags: [tagTravel, tagSight], photoIndex: 22, note: L("車窓から見える青い海が最高だった。", "Blue ocean views right outside the train window.", "기차 창밖으로 펼쳐진 푸른 바다가 정말 멋졌다.", "电车窗外的蓝海太治愈了。", "電車窗外的藍海太療癒了。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 7, name: L("自由が丘パティスリー", "Jiyugaoka Bakery", "지유가오카 베이커리", "自由之丘甜品店", "自由之丘甜點店"), address: L("東京都目黒区", "Meguro, Tokyo", "도쿄 메구로", "东京目黑", "東京目黑"), lat: 35.6073, lon: 139.6685, tags: [tagCafe, tagShop], photoIndex: 4, note: L("苺タルトを購入。午後のご褒美にぴったりの甘さ。", "Picked up a fresh strawberry tart for the afternoon.", "딸기 타르트로 기분 전환.", "买了草莓塔当下午茶。", "買了草莓塔當下午茶。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 8, name: L("中目黒の定食屋", "Nakameguro Diner", "나카메구로 식당", "中目黑定食店", "中目黑定食店"), address: L("東京都目黒区", "Meguro, Tokyo", "도쿄 메구로", "东京目黑", "東京目黑"), lat: 35.6443, lon: 139.6991, tags: [tagFood], photoIndex: 5, note: L("焼き鮭定食でしっかり栄養補給。", "Healthy grilled salmon lunch.", "든든한 연어 정식으로 점심 해결.", "吃了一顿营养均衡的烤三文鱼定食。", "吃了一頓營養均衡的烤鮭魚定食。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 9, name: L("目黒川沿い", "Meguro River", "메구로강 산책로", "目黑川沿岸", "目黑川沿岸"), address: L("東京都目黒区", "Meguro, Tokyo", "도쿄 메구로", "东京目黑", "東京目黑"), lat: 35.6478, lon: 139.6952, tags: [tagWalk], photoIndex: 11, note: L("夕焼けが川面に映ってきれいだった。", "Golden sunset reflected along the river.", "노을이 강물에 비쳐 정말 예뻤다.", "晚霞映在河面上非常美。", "晚霞映在河面上非常美。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 10, name: L("自宅ワークスペース", "Home Workspace", "홈 오피스", "居家书房", "居家書房"), address: L("東京都世田谷区", "Setagaya, Tokyo", "도쿄 세타가야", "东京世田谷", "東京世田谷"), lat: 35.6466, lon: 139.6533, tags: [tagWork, tagStudy], photoIndex: 6, note: L("部屋をリセットして在宅ワークに集中できた。", "Deep focus day working from home.", "책상을 정리하고 재택근무에 집중했다.", "整理好桌面后居家办公很专注。", "整理好桌面後居家辦公很專注。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 11, name: L("六本木アート美術館", "Roppongi Art Museum", "롯폰기 미술관", "六本木美术馆", "六本木美術館"), address: L("東京都港区", "Minato, Tokyo", "도쿄 미나토", "东京港区", "東京港區"), lat: 35.6653, lon: 139.7263, tags: [tagSight], photoIndex: 19, note: L("展示空間が美しくていい刺激をもらえた。", "Inspiring weekend art exhibition.", "빛이 아름다운 전시 공간에서 영감을 얻었다.", "很棒的美术展，收获满满灵感。", "很棒的美術展，收穫滿滿靈感。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 12, name: L("横浜みなとみらい", "Yokohama Bay", "요코하마 미나토미라이", "横滨港未来", "橫濱港未來"), address: L("神奈川県横浜市", "Yokohama", "요코하마", "横滨", "橫濱"), lat: 35.4550, lon: 139.6313, tags: [tagTravel, tagSight, tagFriend], photoIndex: 14, note: L("青空と海風。赤レンガ倉庫まで歩いて気分転換できた。", "Clear skies and ocean breeze by the bay.", "맑은 하늘과 바닷바람을 맞으며 산책했다.", "蓝天配海风，在海滨散步很放松。", "藍天配海風，在海濱散步很放鬆。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 13, name: L("神保町の独立書店", "Jimbocho Bookstore", "진보초 독립서점", "神保町独立书店", "神保町獨立書店"), address: L("東京都千代田区", "Chiyoda, Tokyo", "도쿄 지요다", "东京千代田", "東京千代田"), lat: 35.6959, lon: 139.7576, tags: [tagShop, tagStudy], photoIndex: 20, note: L("デザイン書とエッセイを2冊購入。", "Picked up two design books.", "디자인 책과 에세이를 두 권 샀다.", "买了两本很想看的设计书。", "買了兩本很想看的設計書。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 14, name: L("駒沢公園", "Komazawa Park", "고마자와 공원", "驹泽公园", "駒澤公園"), address: L("東京都世田谷区", "Setagaya", "세타가야", "世田谷", "世田谷"), lat: 35.6266, lon: 139.6615, tags: [tagWalk], photoIndex: 18, note: L("朝の5kmラン。朝日を浴びてエネルギー満タン。", "Refreshing 5K morning run.", "상쾌한 아침 5km 러닝 완료.", "晨跑 5 公里，精力充沛。", "晨跑 5 公里，精力充沛。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 15, name: L("代々木八幡ベーカリー", "Yoyogi Bakery", "요요기 베이커리", "代代木面包房", "代代木麵包店"), address: L("東京都渋谷区", "Shibuya", "시부야", "涉谷", "澀谷"), lat: 35.6687, lon: 139.6897, tags: [tagFood, tagShop], photoIndex: 21, note: L("焼きたてのパンを購入。", "Freshly baked sourdough and pastries.", "갓 구운 빵을 사 왔다.", "买了刚出炉的手工面包。", "買了剛出爐的手工麵包。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 16, name: L("新宿御苑", "Shinjuku Gyoen", "신주쿠 교엔", "新宿御苑", "新宿御苑"), address: L("東京都新宿区", "Shinjuku", "신주쿠", "新宿", "新宿"), lat: 35.6852, lon: 139.7101, tags: [tagSight, tagFriend], photoIndex: 23, note: L("芝生の上でのんびりピクニック。", "Relaxing lawn picnic with iced coffee.", "잔디밭에서 여유로운 피크닉.", "在草坪上悠闲野餐。", "在草坪上悠閒野餐。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 17, name: L("恵比寿ビストロ", "Ebisu Bistro", "에비스 비스트로", "惠比寿餐厅", "惠比壽餐廳"), address: L("東京都渋谷区", "Ebisu, Tokyo", "도쿄 에비스", "东京惠比寿", "東京惠比壽"), lat: 35.6467, lon: 139.7101, tags: [tagFood, tagFriend], photoIndex: 8, note: L("プロジェクト打ち上げディナー。", "Team celebration dinner.", "프로젝트 마무리 저녁 모임.", "项目庆功晚餐。", "專案慶功晚餐。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 18, name: L("二子玉川公園", "Futako Park", "후타코타마가와 공원", "二子玉川公园", "二子玉川公園"), address: L("東京都世田谷区", "Setagaya", "세타가야", "世田谷", "世田谷"), lat: 35.6085, lon: 139.6317, tags: [tagWalk], photoIndex: 7, note: L("ベンチでコーヒーを飲みながら読書。", "Coffee and reading in the afternoon breeze.", "벤치에서 커피를 마시며 독서.", "在长椅上喝着咖啡看书。", "在長椅上喝著咖啡看書。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 19, name: L("鎌倉の竹林庭園", "Kamakura Bamboo Grove", "가마쿠라 대나무 정원", "镰仓竹林庭园", "鎌倉竹林庭園"), address: L("神奈川県鎌倉市", "Kamakura", "가마쿠라", "镰仓", "鎌倉"), lat: 35.3204, lon: 139.5692, tags: [tagTravel, tagSight], photoIndex: 13, note: L("静かな竹林の小径を歩いて落ち着いた。", "Quiet stroll through the bamboo grove.", "조용한 대나무 숲길을 걸으며 휴식했다.", "漫步在安静的竹林小径中。", "漫步在安靜的竹林小徑中。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 20, name: L("お台場海浜公園", "Odaiba Seaside", "오다이바 해변공원", "台场海滨公园", "台場海濱公園"), address: L("東京都港区", "Minato, Tokyo", "도쿄 미나토", "东京港区", "東京港區"), lat: 35.6308, lon: 139.7760, tags: [tagWalk, tagSight], photoIndex: 16, note: L("海沿いを散歩。見晴らしが爽快だった。", "Breezy waterfront walk.", "바닷가를 따라 상쾌하게 산책했다.", "沿着海边散步，视野开阔。", "沿著海邊散步，視野開闊。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 21, name: L("青山フラワーショップ", "Aoyama Florist", "아오야마 플라워샵", "青山花店", "青山花店"), address: L("東京都港区", "Aoyama, Tokyo", "도쿄 아오야마", "东京青山", "東京青山"), lat: 35.6645, lon: 139.7142, tags: [tagShop], photoIndex: 26, note: L("部屋用の小さなブーケを購入。", "Picked up fresh flowers for my desk.", "방에 둘 작은 꽃다발을 샀다.", "买了一束鲜花装点房间。", "買了一束鮮花裝點房間。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 22, name: L("根津の日本庭園", "Nezu Garden", "네즈 일본 정원", "根津日式庭园", "根津日式庭園"), address: L("東京都文京区", "Bunkyo, Tokyo", "도쿄 분쿄", "东京文京", "東京文京"), lat: 35.7201, lon: 139.7607, tags: [tagSight], photoIndex: 25, note: L("苔庭が美しくて穏やかな時間だった。", "Peaceful afternoon in the moss garden.", "고즈넉한 정원에서 여유로운 시간을 보냈다.", "宁静的苔藓庭园让人心情平静。", "寧靜的苔蘚庭園讓人心情平靜。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 23, name: L("六本木展望デッキ", "Roppongi Sky Deck", "롯폰기 전망대", "六本木展望台", "六本木展望台"), address: L("東京都港区", "Roppongi, Tokyo", "도쿄 롯폰기", "东京六本木", "東京六本木"), lat: 35.6605, lon: 139.7292, tags: [tagSight], photoIndex: 17, note: L("夜景と東京タワーの灯りがきれいだった。", "City skyline glowing at twilight.", "노을에서 야경으로 바뀌는 순간이 아름다웠다.", "黄昏到夜景的过渡非常惊艳。", "黃昏到夜景的過渡非常驚豔。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 24, name: L("神楽坂の小径", "Kagurazaka Alley", "카구라자카 골목", "神乐坂小巷", "神樂坂小巷"), address: L("東京都新宿区", "Shinjuku", "신주쿠", "新宿", "新宿"), lat: 35.7016, lon: 139.7405, tags: [tagSight], photoIndex: 15, note: L("雨上がりの石畳と緑がきれいだった。", "Quiet stone alleys after the rain.", "비 갠 뒤 돌담길 산책이 좋았다.", "雨后的石板路和绿意很舒服。", "雨後的石板路和綠意很舒服。"), mood: .high, condition: 4),
            ShowcaseSpot(dayOffsetFromMonthStart: 25, name: L("井の頭公園", "Inokashira Park", "이노카시라 공원", "井之头公园", "井之頭公園"), address: L("東京都武蔵野市", "Musashino", "무사시노", "武藏野", "武藏野"), lat: 35.6997, lon: 139.5705, tags: [tagSight, tagWalk], photoIndex: 12, note: L("季節の花を見ながらカメラ散歩。", "Photo walk around the pond.", "계절 꽃을 보며 카메라 산책을 즐겼다.", "带着相机赏花散步。", "帶著相機賞花散步。"), mood: .veryHigh, condition: 5),
            ShowcaseSpot(dayOffsetFromMonthStart: 26, name: L("代官山の隠れ家カフェ", "Daikanyama Cafe", "다이칸야마 카페", "代官山隐秘咖啡馆", "代官山靜謐咖啡廳"), address: L("東京都渋谷区", "Daikanyama, Tokyo", "도쿄 다이칸야마", "东京代官山", "東京代官山"), lat: 35.6498, lon: 139.7012, tags: [tagCafe, tagWork, tagStudy], photoIndex: 24, note: L("朝のランニングから仕事、夜のカフェまで充実した一日。やりたいことが全部片付いて気分がいい！ #充実 #穏やか", "Great balance today—morning run, focused work, and an evening coffee. Checked off everything on my list! #productive #calm", "아침 러닝부터 업무, 저녁 카페까지 알찬 하루. 계획한 일을 모두 끝내서 기분이 좋다! #알찬하루 #여유", "从晨跑、工作到晚上的咖啡馆，充实又顺心的一天。清单上的事情全都完成了！ #充实 #好心情", "從晨跑、工作到晚上的咖啡廳，充實又順心的一天。清單上的事情全都完成了！ #充實 #好心情"), mood: .veryHigh, condition: 5),
        ]

        var diaryEntriesToSave: [DiaryEntry] = []
        for leadOffset in -6..<0 {
            let d = calendar.date(byAdding: .day, value: leadOffset, to: monthStart)!
            let p = photo(abs(leadOffset) * 3 + 1)
            diaryEntriesToSave.append(DiaryEntry(
                date: d,
                text: L("穏やかな一日。少しずつ習慣が身についてきた。", "Calm and steady day. Habits are sticking.", "차분한 하루. 조금씩 습관이 자리 잡고 있다.", "平静的一天，好习惯慢慢养成了。", "平靜的一天，好習慣慢慢養成了。"),
                mood: leadOffset % 2 == 0 ? .high : .veryHigh,
                conditionScore: 4,
                photoPaths: p.map { [$0] } ?? [],
                favoritePhotoPath: p
            ))
        }

        let totalCurrentMonthDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        let fillUpToDayIndex = totalCurrentMonthDays + 5
        for dayIdx in 0...fillUpToDayIndex {
            let entryDate = calendar.date(byAdding: .day, value: dayIdx, to: monthStart)!
            let spot = curatedEntries[dayIdx % curatedEntries.count]
            let photoIdx = dayIdx < curatedEntries.count ? spot.photoIndex : (dayIdx * 5 + 3) % 27
            let mainPhoto = photo(photoIdx)
            var paths: [String] = []
            if let mainPhoto { paths.append(mainPhoto) }
            if dayIdx == daysFromMonthStart || dayIdx == 5 || dayIdx == 12 {
                if let p2 = photo(photoIdx + 1), !paths.contains(p2) { paths.append(p2) }
                if let p3 = photo(photoIdx + 2), !paths.contains(p3) { paths.append(p3) }
            }
            let includeLocation = dayIdx < totalCurrentMonthDays
            let location = DiaryLocation(
                name: spot.name,
                address: spot.address,
                latitude: spot.lat,
                longitude: spot.lon,
                mapItemURL: nil,
                photoPaths: mainPhoto.map { [$0] } ?? [],
                visitTags: spot.tags
            )
            diaryEntriesToSave.append(DiaryEntry(
                date: entryDate,
                text: spot.note,
                mood: spot.mood,
                conditionScore: spot.condition,
                locations: includeLocation ? [location] : [],
                locationName: includeLocation ? spot.name : nil,
                latitude: includeLocation ? spot.lat : nil,
                longitude: includeLocation ? spot.lon : nil,
                photoPaths: paths,
                locationPhotoPaths: includeLocation ? (mainPhoto.map { [$0] } ?? []) : [],
                favoritePhotoPath: mainPhoto
            ))
        }

        let travelPins: [(monthsAgo: Int, dayOffset: Int, name: String, address: String, lat: Double, lon: Double, tags: [String], photoIdx: Int, note: String)] = [
            (1, 3, L("聖水カフェ通り", "Seongsu Cafe St.", "성수동 카페거리", "圣水洞咖啡街", "聖水洞咖啡街"), L("韓国 ソウル", "Seoul, Korea", "서울 성동구", "韩国 首尔", "韓國 首爾"), 37.5445, 127.0560, [tagTravel, tagCafe], 0, L("ソウル週末旅。", "Weekend trip in Seoul.", "성수동 카페 투어.", "首尔周末旅行。", "首爾週末旅行。")),
            (1, 4, L("海雲台ビーチ", "Haeundae Beach", "해운대 해변", "海云台海滩", "海雲台海灘"), L("韓国 釜山", "Busan, Korea", "부산 해운대", "韩国 釜山", "韓國 釜山"), 35.1587, 129.1604, [tagTravel, tagSight], 10, L("海沿いの散歩道。", "Ocean walk in Busan.", "바다 산책.", "海边漫步。", "海邊漫步。")),
            (2, 10, L("九份老街", "Jiufen Old St.", "지우펀 옛거리", "九份老街", "九份老街"), L("台湾 新北市", "Taipei, Taiwan", "대만 타이베이", "台湾 新北", "台灣 新北"), 25.1099, 121.8452, [tagTravel, tagSight], 17, L("夕暮れの提灯。", "Lanterns at dusk.", "노을 진 골목.", "黄昏灯笼街。", "黃昏燈籠街。")),
            (2, 11, L("永康街", "Yongkang St.", "융캉제", "永康街", "永康街"), L("台湾 台北市", "Taipei, Taiwan", "대만 타이베이", "台湾 台北", "台灣 台北"), 25.0330, 121.5299, [tagTravel, tagFood], 5, L("小籠包とマンゴー。", "Dim sum & mango ice.", "맛집 탐방.", "小笼包和芒果冰。", "小籠包和芒果冰。")),
            (3, 5, L("ビクトリア・ピーク", "Victoria Peak", "빅토리아 피크", "太平山顶", "太平山頂"), L("香港", "Hong Kong", "홍콩", "香港", "香港"), 22.2759, 114.1455, [tagTravel, tagSight], 17, L("百万ドルの夜景。", "Night skyline view.", "화려한 야경.", "维港夜景。", "維港夜景。")),
            (4, 14, L("ワット・アルン", "Wat Arun", "왓 아룬", "郑王庙", "鄭王廟"), L("タイ バンコク", "Bangkok, Thailand", "태국 방콕", "泰国 曼谷", "泰國 曼谷"), 13.7437, 100.4889, [tagTravel, tagSight], 11, L("川沿いの夕焼け。", "Riverside sunset.", "강변 노을.", "湄南河日落。", "湄南河日落。")),
            (4, 18, L("マリーナベイ", "Marina Bay", "마리나 베이", "滨海湾", "濱海灣"), L("シンガポール", "Singapore", "싱가포르", "新加坡", "新加坡"), 1.2834, 103.8607, [tagTravel, tagSight], 14, L("海風と建築。", "Bayfront walk.", "바닷바람 산책.", "海湾漫步。", "海灣漫步。")),
            (5, 8, L("タモンビーチ", "Tumon Beach", "투몬 비치", "杜梦湾", "杜夢灣"), L("グアム", "Guam", "괌", "关岛", "關島"), 13.5112, 144.8058, [tagTravel, tagSight], 10, L("透き通る海。", "Crystal clear water.", "투명한 바다.", "清澈大海。", "清澈大海。")),
            (6, 12, L("シドニー・ハーバー", "Sydney Harbour", "시드니 하버", "悉尼港", "雪梨港"), L("オーストラリア", "Sydney, Australia", "호주 시드니", "澳大利亚 悉尼", "澳洲 雪梨"), -33.8568, 151.2153, [tagTravel, tagSight], 14, L("港の青空。", "Sunny harbour view.", "시원한 항구 풍경.", "阳光海港。", "陽光海港。")),
            (2, 22, L("嵐山の竹林", "Arashiyama", "아라시야마 대나무숲", "岚山竹林", "嵐山竹林"), L("京都府京都市", "Kyoto, Japan", "일본 교토", "日本 京都", "日本 京都"), 35.0170, 135.6713, [tagTravel, tagSight], 13, L("早朝の竹林。", "Early morning stroll.", "이른 아침 산책.", "清晨竹林。", "清晨竹林。")),
            (3, 18, L("大通公園", "Odori Park", "오도리 공원", "大通公园", "大通公園"), L("北海道札幌市", "Sapporo, Japan", "일본 삿포로", "日本 札幌", "日本 札幌"), 43.0597, 141.3469, [tagTravel, tagFood], 16, L("北海道旅。", "Hokkaido trip.", "홋카이도 여행.", "北海道之旅。", "北海道之旅。")),
            (5, 20, L("古宇利島ビーチ", "Kouri Island", "고우리 섬", "古宇利岛", "古宇利島"), L("沖縄県", "Okinawa, Japan", "일본 오키나와", "日本 冲绳", "日本 沖繩"), 26.7064, 128.0185, [tagTravel, tagSight], 10, L("エメラルドの海。", "Emerald ocean drive.", "에메랄드빛 바다.", "翡翠海滩。", "翡翠海灘。")),
        ]
        for pin in travelPins {
            guard let baseMonth = calendar.date(byAdding: .month, value: -pin.monthsAgo, to: monthStart),
                  let entryDate = calendar.date(byAdding: .day, value: pin.dayOffset, to: baseMonth) else { continue }
            let p = photo(pin.photoIdx)
            let loc = DiaryLocation(
                name: pin.name,
                address: pin.address,
                latitude: pin.lat,
                longitude: pin.lon,
                mapItemURL: nil,
                photoPaths: p.map { [$0] } ?? [],
                visitTags: pin.tags
            )
            diaryEntriesToSave.append(DiaryEntry(
                date: entryDate,
                text: pin.note,
                mood: .veryHigh,
                conditionScore: 5,
                locations: [loc],
                locationName: pin.name,
                latitude: pin.lat,
                longitude: pin.lon,
                photoPaths: p.map { [$0] } ?? [],
                locationPhotoPaths: p.map { [$0] } ?? [],
                favoritePhotoPath: p
            ))
        }
        for entry in diaryEntriesToSave {
            modelContext.insert(SDDiaryEntry(domain: entry))
        }

        func timedEvent(_ title: String, dayFromMonthStart: Int, startHour: Int, startMinute: Int = 0, durationMinutes: Int = 60, category: String) -> CalendarEvent {
            let base = calendar.date(byAdding: .day, value: dayFromMonthStart, to: monthStart)!
            let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: base)!
            let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start)!
            return CalendarEvent(title: title, startDate: start, endDate: end, calendarName: category)
        }
        func allDayEvent(_ title: String, dayFromMonthStart: Int, spanDays: Int, category: String) -> CalendarEvent {
            let start = calendar.date(byAdding: .day, value: dayFromMonthStart, to: monthStart)!
            let end = calendar.date(byAdding: .day, value: spanDays, to: start)!
            return CalendarEvent(title: title, startDate: start, endDate: end, calendarName: category, isAllDay: true)
        }

        let showcaseEvents: [CalendarEvent] = [
            timedEvent(L("チーム朝会", "Team Standup", "팀 아침 회의", "团队晨会", "團隊晨會"), dayFromMonthStart: daysFromMonthStart, startHour: 9, startMinute: 30, durationMinutes: 30, category: catWork),
            timedEvent(L("代官山カフェでランチ", "Cafe Lunch", "카페 런치", "咖啡馆午餐", "咖啡廳午餐"), dayFromMonthStart: daysFromMonthStart, startHour: 12, startMinute: 30, durationMinutes: 60, category: catPersonal),
            timedEvent(L("デザインレビュー", "Design Review", "디자인 리뷰", "设计评审", "設計評審"), dayFromMonthStart: daysFromMonthStart, startHour: 15, startMinute: 0, durationMinutes: 60, category: catWork),
            timedEvent(L("ナイトラン 5km", "Evening Run 5K", "야간 러닝 5km", "夜跑 5公里", "夜跑 5公里"), dayFromMonthStart: daysFromMonthStart, startHour: 19, startMinute: 0, durationMinutes: 45, category: catHealth),

            timedEvent(L("朝の散歩", "Morning Walk", "아침 산책", "晨间散步", "晨間散步"), dayFromMonthStart: 1, startHour: 7, startMinute: 30, durationMinutes: 30, category: catHealth),
            timedEvent(L("企画ミーティング", "Product Sync", "기획 미팅", "策划会议", "企劃會議"), dayFromMonthStart: 2, startHour: 10, startMinute: 0, durationMinutes: 60, category: catWork),
            timedEvent(L("友人とランチ", "Lunch w/ Alex", "친구와 점심", "朋友聚餐", "朋友聚餐"), dayFromMonthStart: 2, startHour: 12, startMinute: 30, durationMinutes: 90, category: catPersonal),
            timedEvent(L("英語レッスン", "English Class", "영어 수업", "英语课", "英語課"), dayFromMonthStart: 3, startHour: 19, startMinute: 0, durationMinutes: 60, category: catStudy),
            timedEvent(L("デザイン定例", "Design Sync", "디자인 정례", "设计例会", "設計例會"), dayFromMonthStart: 4, startHour: 14, startMinute: 0, durationMinutes: 60, category: catWork),
            allDayEvent(L("鎌倉・湘南 小旅行", "Beach Weekend", "가마쿠라 여행", "海滨周末游", "海濱週末遊"), dayFromMonthStart: 5, spanDays: 2, category: catTravel),
            timedEvent(L("ジム", "Gym", "헬스장", "健身房", "健身房"), dayFromMonthStart: 7, startHour: 18, startMinute: 30, durationMinutes: 60, category: catHealth),
            timedEvent(L("仕様確認", "Spec Review", "스펙 확인", "需求确认", "規格確認"), dayFromMonthStart: 8, startHour: 11, startMinute: 0, durationMinutes: 60, category: catWork),
            timedEvent(L("読書会", "Book Club", "독서 모임", "读书会", "讀書會"), dayFromMonthStart: 9, startHour: 20, startMinute: 0, durationMinutes: 60, category: catStudy),
            timedEvent(L("歯科検診", "Dentist", "치과 검진", "牙科检查", "牙科檢查"), dayFromMonthStart: 10, startHour: 10, startMinute: 30, durationMinutes: 45, category: catHealth),
            timedEvent(L("美術館めぐり", "Art Museum", "미술관 전시", "逛美术馆", "逛美術館"), dayFromMonthStart: 11, startHour: 14, startMinute: 0, durationMinutes: 120, category: catPersonal),
            allDayEvent(L("横浜みなとみらい散策", "Bay Day Trip", "요코하마 산책", "港湾一日游", "港灣一日遊"), dayFromMonthStart: 12, spanDays: 1, category: catTravel),
            timedEvent(L("週次ふりかえり", "Weekly Retro", "주간 회고", "周复盘", "週回顧"), dayFromMonthStart: 13, startHour: 18, startMinute: 0, durationMinutes: 45, category: catWork),
            timedEvent(L("朝ラン 5km", "Morning 5K", "아침 러닝", "晨跑 5km", "晨跑 5km"), dayFromMonthStart: 14, startHour: 7, startMinute: 0, durationMinutes: 40, category: catHealth),
            timedEvent(L("リリース準備", "Release Prep", "출시 준비", "发布准备", "發佈準備"), dayFromMonthStart: 15, startHour: 15, startMinute: 0, durationMinutes: 90, category: catWork),
            timedEvent(L("公園ピクニック", "Park Picnic", "공원 피크닉", "公园野餐", "公園野餐"), dayFromMonthStart: 16, startHour: 12, startMinute: 0, durationMinutes: 150, category: catPersonal),
            timedEvent(L("打ち上げディナー", "Team Dinner", "회식 저녁", "庆功晚餐", "慶功晚餐"), dayFromMonthStart: 17, startHour: 19, startMinute: 30, durationMinutes: 120, category: catPersonal),
            timedEvent(L("ヨガ", "Yoga", "요가", "瑜伽", "瑜伽"), dayFromMonthStart: 18, startHour: 19, startMinute: 0, durationMinutes: 60, category: catHealth),
            allDayEvent(L("箱根・温泉リトリート", "Hot Spring Trip", "온천 여행", "温泉度假", "溫泉度假"), dayFromMonthStart: 19, spanDays: 2, category: catTravel),
            timedEvent(L("プレゼン準備", "Deck Prep", "발표 준비", "演讲准备", "簡報準備"), dayFromMonthStart: 21, startHour: 14, startMinute: 0, durationMinutes: 90, category: catWork),
            timedEvent(L("美容院", "Haircut", "미용실", "理发", "剪髮"), dayFromMonthStart: 22, startHour: 13, startMinute: 0, durationMinutes: 90, category: catPersonal),
            timedEvent(L("英語シャドーイング", "Language Study", "영어 회화", "英语口语", "英語口說"), dayFromMonthStart: 23, startHour: 20, startMinute: 0, durationMinutes: 45, category: catStudy),
            timedEvent(L("ジム", "Gym", "헬스장", "健身房", "健身房"), dayFromMonthStart: 24, startHour: 18, startMinute: 30, durationMinutes: 60, category: catHealth),
            timedEvent(L("月次レビュー", "Monthly Review", "월간 리뷰", "月度复盘", "月度回顧"), dayFromMonthStart: 25, startHour: 16, startMinute: 0, durationMinutes: 60, category: catWork),
            allDayEvent(L("京都・秋の週末旅", "Kyoto Weekend", "교토 주말 여행", "京都周末游", "京都週末遊"), dayFromMonthStart: min(totalCurrentMonthDays - 2, daysFromMonthStart + 1), spanDays: 2, category: catTravel),

            timedEvent(L("定例MTG", "Weekly Sync", "정기 미팅", "周例会", "週例會"), dayFromMonthStart: daysFromMonthStart + 4, startHour: 10, startMinute: 0, durationMinutes: 60, category: catWork),
            timedEvent(L("ジム", "Gym", "헬스장", "健身房", "健身房"), dayFromMonthStart: daysFromMonthStart + 4, startHour: 19, startMinute: 0, durationMinutes: 60, category: catHealth),
            timedEvent(L("カフェ作業", "Cafe Study", "카페 작업", "咖啡馆学习", "咖啡廳學習"), dayFromMonthStart: daysFromMonthStart + 5, startHour: 14, startMinute: 0, durationMinutes: 90, category: catStudy),
            timedEvent(L("デザインレビュー", "Design Review", "디자인 리뷰", "设计评审", "設計評審"), dayFromMonthStart: daysFromMonthStart + 6, startHour: 15, startMinute: 0, durationMinutes: 60, category: catWork),
            timedEvent(L("友人とディナー", "Dinner Out", "친구와 저녁", "朋友晚餐", "朋友晚餐"), dayFromMonthStart: daysFromMonthStart + 7, startHour: 19, startMinute: 30, durationMinutes: 120, category: catPersonal),
            allDayEvent(L("軽井沢 週末旅", "Mountain Trip", "주말 여행", "周末短途游", "週末短途遊"), dayFromMonthStart: daysFromMonthStart + 8, spanDays: 2, category: catTravel),
            timedEvent(L("朝ラン 5km", "Morning Run", "아침 러닝", "晨跑 5km", "晨跑 5km"), dayFromMonthStart: daysFromMonthStart + 10, startHour: 7, startMinute: 0, durationMinutes: 40, category: catHealth),
            timedEvent(L("企画会議", "Planning", "기획 회의", "策划会", "企劃會"), dayFromMonthStart: daysFromMonthStart + 11, startHour: 11, startMinute: 0, durationMinutes: 60, category: catWork),
            timedEvent(L("英語レッスン", "English", "영어 수업", "英语课", "英語課"), dayFromMonthStart: daysFromMonthStart + 12, startHour: 20, startMinute: 0, durationMinutes: 60, category: catStudy),
            timedEvent(L("ヨガ", "Yoga", "요가", "瑜伽", "瑜伽"), dayFromMonthStart: daysFromMonthStart + 13, startHour: 18, startMinute: 30, durationMinutes: 60, category: catHealth),
            timedEvent(L("忘年会", "Year-End Party", "송년회", "年终聚会", "年終聚會"), dayFromMonthStart: daysFromMonthStart + 14, startHour: 19, startMinute: 0, durationMinutes: 150, category: catPersonal),
            allDayEvent(L("展示会・イベント", "Art Expo", "전시회", "艺术展", "藝術展"), dayFromMonthStart: daysFromMonthStart + 15, spanDays: 2, category: catPersonal),
            timedEvent(L("週次ふりかえり", "Weekly Retro", "주간 회고", "周复盘", "週回顧"), dayFromMonthStart: daysFromMonthStart + 17, startHour: 17, startMinute: 0, durationMinutes: 45, category: catWork),
            timedEvent(L("読書会", "Book Club", "독서 모임", "读书会", "讀書會"), dayFromMonthStart: daysFromMonthStart + 18, startHour: 20, startMinute: 0, durationMinutes: 60, category: catStudy),
            timedEvent(L("ジム", "Gym", "헬스장", "健身房", "健身房"), dayFromMonthStart: daysFromMonthStart + 19, startHour: 19, startMinute: 0, durationMinutes: 60, category: catHealth),
            timedEvent(L("ランチ会", "Team Lunch", "점심 모임", "午餐聚会", "午餐聚會"), dayFromMonthStart: daysFromMonthStart + 20, startHour: 12, startMinute: 30, durationMinutes: 60, category: catPersonal),
            allDayEvent(L("クリスマス旅行", "Holiday Trip", "연말 여행", "圣诞旅行", "聖誕旅行"), dayFromMonthStart: daysFromMonthStart + 21, spanDays: 2, category: catTravel),
        ]
        for event in showcaseEvents {
            modelContext.insert(SDCalendarEvent(domain: event))
        }

        let showcaseTasks: [Task] = [
            Task(title: L("デザインスライドを仕上げる", "Finish design deck", "디자인 슬라이드 마무리", "完成设计演示文稿", "完成設計簡報"), detail: L("最終チェックと共有", "Final check & share", "최종 확인 및 공유", "最终检查并分享", "最終檢查並分享"), startDate: today, endDate: today, priority: .high, isCompleted: false),
            Task(title: L("週末の旅行ホテルを確認", "Confirm weekend hotel", "주말 여행 호텔 확인", "确认周末旅行酒店", "確認週末旅行飯店"), detail: L("チェックイン時間をメモ", "Note check-in time", "체크인 시간 메모", "记录入住时间", "記錄入住時間"), startDate: today, endDate: today, priority: .medium, isCompleted: false),
            Task(title: L("朝のメール返信", "Reply to morning emails", "아침 이메일 답장", "回复早间邮件", "回覆早間郵件"), startDate: today, endDate: today, priority: .low, isCompleted: true),
            Task(title: L("写真アルバムを整理する", "Organize photo album", "사진 앨범 정리하기", "整理照片相册", "整理照片相簿"), startDate: day(1), endDate: day(2), priority: .medium, isCompleted: false),
        ]
        for task in showcaseTasks {
            modelContext.insert(SDTask(domain: task))
        }

        let memoText = L(
            "・週末の持ち物：カメラ、充電器、文庫本\n・行きたいカフェ：清澄白河のロースタリー\n・今月の目標：朝の散歩と読書を毎日つづける",
            "• Weekend bag: camera, charger, book\n• Cafe to try: Kiyosumi Roastery\n• Monthly goal: daily walk & 20m reading",
            "• 주말 준비물: 카메라, 충전기, 책\n• 가고 싶은 카페: 성수동 로스터리\n• 이번 달 목표: 아침 산책과 독서 매일 이어가기",
            "• 周末清单：相机、充电器、随身书\n• 想去的店：手冲咖啡烘焙馆\n• 本月目标：坚持每天晨间散步和阅读",
            "• 週末清單：相機、充電器、隨身書\n• 想去的店：手沖咖啡烘焙館\n• 本月目標：堅持每天晨間散步和閱讀"
        )
        modelContext.insert(SDMemoPad(text: memoText, lastUpdatedAt: today))

        let showcaseHabits: [Habit] = [
            Habit(title: L("朝の散歩", "Morning Walk", "아침 산책", "晨间散步", "晨間散步"), iconName: "figure.walk", colorHex: "#0EA5E9", schedule: .daily, createdAt: day(-160)),
            Habit(title: L("読書 20分", "Read 20 min", "독서 20분", "阅读 20分钟", "閱讀 20分鐘"), iconName: "book.fill", colorHex: "#22C55E", schedule: .daily, createdAt: day(-160)),
            Habit(title: L("瞑想 10分", "Meditate 10m", "명상 10분", "冥想 10分钟", "冥想 10分鐘"), iconName: "brain.head.profile", colorHex: "#8B5CF6", schedule: .daily, createdAt: day(-160)),
            Habit(title: L("筋トレ・ストレッチ", "Workout", "근력 운동", "力量拉伸", "肌力伸展"), iconName: "flame.fill", colorHex: "#F97316", schedule: .weekdays, createdAt: day(-160)),
            Habit(title: L("水を2L飲む", "Drink 2L Water", "물 2L 마시기", "喝水 2L", "喝水 2L"), iconName: "drop.fill", colorHex: "#06B6D4", schedule: .daily, createdAt: day(-160)),
        ]
        for (idx, habit) in showcaseHabits.enumerated() {
            let sd = SDHabit(domain: habit)
            sd.orderIndex = idx
            modelContext.insert(sd)
        }

        for offset in -150...0 {
            let d = day(offset)
            for (hIdx, habit) in showcaseHabits.enumerated() where habit.schedule.isActive(on: d) {
                let completed: Bool
                if offset >= -14 && hIdx < 2 {
                    completed = true
                } else if offset >= -7 && hIdx == 2 {
                    completed = true
                } else if offset == 0 && hIdx == 4 {
                    completed = false
                } else {
                    let hash = abs((offset * 31) ^ (hIdx * 17 + 7)) % 10
                    completed = hash < 8
                }
                modelContext.insert(SDHabitRecord(domain: HabitRecord(habitID: habit.id, date: d, isCompleted: completed)))
            }
        }

        let showcaseAnniversaries: [Anniversary] = [
            Anniversary(title: L("沖縄・夏休み旅行", "Okinawa Beach Trip", "오키나와 여름 여행", "冲绳海岛旅行", "沖繩海島旅行"), targetDate: day(42), type: .countdown, repeatsYearly: false,
                        startDate: day(-60), startLabel: L("予約した日", "Booked", "예약한 날", "预订日", "預訂日"), endLabel: L("出発まで", "until takeoff", "출발까지", "距出发", "距出發")),
            Anniversary(title: L("英語試験（TOEIC）", "Language Exam", "영어 시험 (TOEIC)", "英语考试", "英語考試"), targetDate: day(24), type: .countdown, repeatsYearly: false,
                        startDate: day(-90), startLabel: L("勉強開始", "Started", "공부 시작", "开始备考", "開始備考"), endLabel: L("本番まで", "until exam", "시험까지", "距考试", "距考試")),
            Anniversary(title: L("誕生日", "Birthday", "생일", "生日", "生日"), targetDate: day(18), type: .countdown, repeatsYearly: true),
            Anniversary(title: L("lifelifyを始めて", "Using lifelify", "lifelify 시작", "使用 lifelify", "使用 lifelify"), targetDate: calendar.date(byAdding: .year, value: -1, to: today)!,
                        type: .since, repeatsYearly: true),
            Anniversary(title: L("パリ旅行・貯金目標", "Paris Trip Goal", "파리 여행 목표", "巴黎旅行目标", "巴黎旅行目標"), targetDate: day(85), type: .countdown, repeatsYearly: false,
                        startDate: day(-120), startLabel: L("スタート", "Start", "시작", "起点", "起點"), endLabel: L("目標日まで", "until goal", "목표일까지", "距目标", "距目標")),
        ]
        for (idx, ann) in showcaseAnniversaries.enumerated() {
            let sd = SDAnniversary(domain: ann)
            sd.orderIndex = idx
            modelContext.insert(sd)
        }

        for offset in -13...0 {
            let d = day(offset)
            var summary = HealthSummary(date: d)
            let wave = [0, 650, -300, 900, 1400, 400, -200, 1100, 800, 500, 1600, 300, 950, 1220][offset + 13]
            summary.steps = 8_200 + wave
            summary.sleepHours = [7.2, 6.8, 7.5, 7.1, 7.8, 8.1, 7.4, 7.0, 7.6, 7.3, 7.9, 7.2, 7.5, 7.7][offset + 13]
            summary.activeEnergy = Double(380 + ((offset + 13) % 5) * 35)
            summary.moveMinutes = Double(52 + ((offset + 13) % 4) * 6)
            summary.exerciseMinutes = Double(32 + ((offset + 13) % 4) * 5)
            summary.standHours = Double(11 + ((offset + 13) % 2))
            summary.activeEnergyGoal = 450
            summary.moveMinutesGoal = 60
            summary.exerciseMinutesGoal = 30
            summary.standHoursGoal = 12.0
            summary.fitnessMoveMode = .energy
            summary.weatherCondition = L("晴れ", "Sunny", "맑음", "晴", "晴朗")
            summary.highTemperature = 21
            summary.lowTemperature = 12
            summary.sleepEnd = calendar.date(bySettingHour: 7, minute: 5, second: 0, of: d)
            summary.sleepStart = summary.sleepEnd?.addingTimeInterval(-((summary.sleepHours ?? 7.5) * 3_600 + 600))
            if let start = summary.sleepStart, let end = summary.sleepEnd {
                let s1 = start.addingTimeInterval(2_400)
                let s2 = s1.addingTimeInterval(5_400)
                let s3 = s2.addingTimeInterval(4_800)
                let s4 = s3.addingTimeInterval(600)
                let s5 = s4.addingTimeInterval(4_500)
                let s6 = s5.addingTimeInterval(4_200)
                summary.sleepStages = [
                    SleepStage(start: start, end: s1, stage: .core),
                    SleepStage(start: s1, end: s2, stage: .deep),
                    SleepStage(start: s2, end: s3, stage: .core),
                    SleepStage(start: s3, end: s4, stage: .awake),
                    SleepStage(start: s4, end: s5, stage: .rem),
                    SleepStage(start: s5, end: s6, stage: .deep),
                    SleepStage(start: s6, end: end, stage: .core),
                ]
            }
            modelContext.insert(SDHealthSummary(domain: summary))
        }

        let letterPhoto1 = photo(10).map { [$0] } ?? []
        let letterPhoto2 = photo(13).map { [$0] } ?? []
        let showcaseLetters: [Letter] = [
            Letter(
                content: L(
                    "1年後の自分へ。毎日の小さな記録が、きっと今の自分を支えてくれているはず。自分のペースで毎日を楽しめていますか？",
                    "To my future self one year from now: I hope these daily logs remind you how far you've come. Keep enjoying each day at your own pace.",
                    "1년 뒤의 나에게. 매일의 작은 기록이 지금의 나를 단단하게 만들어 주었을 거야. 나만의 속도로 매일을 잘 즐기고 있니?",
                    "写给一年后的自己：希望这些每天的小记录，能让你看到一路走来的积累。现在也在按自己的节奏生活吗？",
                    "寫給一年後的自己：希望這些每天的小紀錄，能讓你看到一路走來的累積。現在也在按自己的步調生活嗎？"
                ),
                photoPaths: letterPhoto1,
                createdAt: calendar.date(byAdding: .year, value: -1, to: today)!,
                deliveryType: .fixed,
                deliveryDate: today.addingTimeInterval(-3_600),
                status: .sealed,
                openedAt: nil,
                dismissedFromHome: false
            ),
            Letter(
                content: L(
                    "海を見ながら書いた手紙。忙しい季節が来ても、週末に深呼吸する時間を忘れずにいよう。",
                    "Written by the coast. Even during busy weeks, don't forget to pause and take a deep breath on weekends.",
                    "바다를 보며 쓴 편지. 바쁜 계절이 와도 주말에는 꼭 숨 고르는 시간을 갖자.",
                    "在海边写下的信。即使再忙，周末也别忘了留出深呼吸的时间。",
                    "在海邊寫下的信。即使再忙，週末也別忘了留出深呼吸的時間。"
                ),
                photoPaths: letterPhoto1,
                createdAt: day(-180),
                deliveryType: .fixed,
                deliveryDate: day(-14),
                status: .opened,
                openedAt: day(-14),
                dismissedFromHome: true
            ),
            Letter(
                content: L(
                    "新しい習慣を始めた日の記録。朝の散歩と読書、ちゃんと続いているかな？小さな積み上げが一番強い！",
                    "Note from day one of my new routine—are morning walks and daily reading still going strong?",
                    "새 습관을 시작한 날의 기록. 아침 산책과 독서, 지금도 꾸준히 이어가고 있겠지?",
                    "开始新习惯那天的记录：晨间散步和阅读现在还坚持着吗？点滴积累最有力量！",
                    "開始新習慣那天的紀錄：晨間散步和閱讀現在還堅持著嗎？點滴累積最有力量！"
                ),
                photoPaths: letterPhoto2,
                createdAt: day(-90),
                deliveryType: .fixed,
                deliveryDate: day(-3),
                status: .opened,
                openedAt: day(-3),
                dismissedFromHome: true
            ),
        ]
        for letter in showcaseLetters {
            modelContext.insert(SDLetter(domain: letter))
        }

        let supermarket = ShoppingPlace(name: L("スーパー", "Grocery", "마트", "超市", "超市"), orderIndex: 0)
        let drugstore = ShoppingPlace(name: L("ドラッグストア", "Pharmacy", "드럭스토어", "药妆店", "藥妝店"), orderIndex: 1)
        let stationery = ShoppingPlace(name: L("文房具・雑貨", "Stationery", "문구·잡화", "文具杂货", "文具雜貨"), orderIndex: 2)
        for place in [supermarket, drugstore, stationery] {
            modelContext.insert(SDShoppingPlace(id: place.id, name: place.name, orderIndex: place.orderIndex))
        }
        let shoppingItems: [ShoppingItem] = [
            ShoppingItem(title: L("牛乳", "Organic Milk", "우유", "纯牛奶", "鮮奶"), note: L("成分無調整 1L", "1L whole", "무지방 1L", "1L 装", "1L 裝"), placeID: supermarket.id, createdAt: today),
            ShoppingItem(title: L("食パン", "Sourdough Bread", "식빵", "吐司面包", "吐司麵包"), note: L("6枚切り", "1 loaf", "6조각", "厚切", "厚片"), placeID: supermarket.id, createdAt: today.addingTimeInterval(1)),
            ShoppingItem(title: L("アボカド", "Avocados", "아보카도", "牛油果", "酪梨"), note: L("食べ頃を2個", "2 ripe", "잘 익은 것 2개", "2个熟的", "2顆熟的"), placeID: supermarket.id, createdAt: today.addingTimeInterval(2)),
            ShoppingItem(title: L("コーヒー豆", "Coffee Beans", "원두 커피", "咖啡豆", "咖啡豆"), note: L("中煎り・200g", "Medium roast 200g", "미디엄 로스트 200g", "中度烘焙 200g", "中焙 200g"), placeID: supermarket.id, createdAt: today.addingTimeInterval(3)),
            ShoppingItem(title: L("トマト", "Cherry Tomatoes", "방울토마토", "番茄", "番茄"), placeID: supermarket.id, createdAt: today.addingTimeInterval(4)),
            ShoppingItem(title: L("化粧水", "Facial Toner", "토너", "爽肤水", "化妝水"), note: L("詰め替え用", "Refill pack", "리필용", "补充装", "補充包"), placeID: drugstore.id, createdAt: today.addingTimeInterval(5)),
            ShoppingItem(title: L("歯ブラシ", "Toothbrush", "칫솔", "牙刷", "牙刷"), placeID: drugstore.id, createdAt: today.addingTimeInterval(6)),
            ShoppingItem(title: L("ハンドクリーム", "Hand Cream", "핸드크림", "护手霜", "護手霜"), placeID: drugstore.id, createdAt: today.addingTimeInterval(7)),
            ShoppingItem(title: L("方眼ノート A5", "Grid Notebook A5", "모눈 노트 A5", "A5 方格笔记本", "A5 方格筆記本"), placeID: stationery.id, createdAt: today.addingTimeInterval(8)),
            ShoppingItem(title: L("ボールペン替芯", "Pen Refill", "볼펜 리필심", "中性笔替芯", "原子筆筆芯"), note: L("0.5mm 黒", "0.5mm Black", "0.5mm 검정", "0.5mm 黑色", "0.5mm 黑色"), placeID: stationery.id, createdAt: today.addingTimeInterval(9)),
        ]
        for item in shoppingItems {
            modelContext.insert(SDShoppingItem(domain: item))
        }

        do {
            try modelContext.save()
            tasks = try modelContext.fetch(FetchDescriptor<SDTask>()).map { Task(sd: $0) }
            let reloadedDiaries = try modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).map { DiaryEntry(sd: $0) }
            diaryEntries = Self.normalizeDiaryEntries(reloadedDiaries)
            habits = try modelContext.fetch(FetchDescriptor<SDHabit>(sortBy: [SortDescriptor(\.orderIndex)])).map { Habit(sd: $0) }
            habitRecords = try modelContext.fetch(FetchDescriptor<SDHabitRecord>()).map { HabitRecord(sd: $0) }
            anniversaries = try modelContext.fetch(FetchDescriptor<SDAnniversary>(sortBy: [SortDescriptor(\.orderIndex)])).map { Anniversary(sd: $0) }
            try reloadSimulatorDemoHealthSummaries()
            calendarEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).map { CalendarEvent(sd: $0) }
            if let memo = try modelContext.fetch(FetchDescriptor<SDMemoPad>()).first { memoPad = MemoPad(sd: memo) }
            letters = try modelContext.fetch(FetchDescriptor<SDLetter>()).map { Letter(sd: $0) }
            try shoppingStore.reload()
            eventsCache.removeAll()
            UserDefaults.standard.set(true, forKey: InitialPermissionsState.completedKey)
            UserDefaults.standard.set(true, forKey: WallpaperCalendarAnnouncementState.hasSeenKey)
            UserDefaults.standard.set(true, forKey: "hasSeenLetterWelcome")
            UserDefaults.standard.set(true, forKey: "showMoodOnReviewCalendar")
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            AppLogger.data.error("ASO showcase save failed: \(error)")
        }
    }
}

/// Renders the actual WallpaperCalendarRenderView on the simulator lock screen layout
/// for authentic App Store screenshot capture.
struct ASOWallpaperLockScreenCaptureView: View {
    @State private var snapshot: WallpaperCalendarSnapshot?
    private let settings = WallpaperCalendarSettings(
        layoutPreset: .standard,
        privacyMode: .details,
        appearance: .dark
    )

    private var backgroundImage: UIImage? {
        let url = ASOScreenshotShowcase.photoSourceDirectory.appendingPathComponent("photo_18.jpg")
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        ZStack {
            if let snapshot {
                WallpaperCalendarRenderView(
                    snapshot: snapshot,
                    settings: settings,
                    backgroundImage: backgroundImage,
                    isDarkAppearance: true
                )
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 2) {
                Text(lockDateString)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                Text("9:41")
                    .font(.system(size: 102, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
                Spacer()
                HStack {
                    lockCircleButton(systemName: "flashlight.off.fill")
                    Spacer()
                    lockCircleButton(systemName: "camera.fill")
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 34)
            }
            .padding(.top, 56)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            snapshot = try? WallpaperCalendarRenderer().makePreviewSnapshot(settings: settings, now: Date())
        }
    }

    private var lockDateString: String {
        let lang = ASOShowcaseLang.current
        let f = DateFormatter()
        f.locale = Locale(identifier: lang.localeIdentifier)
        switch lang {
        case .ja: f.dateFormat = "M月d日 EEEE"
        case .en: f.dateFormat = "EEEE, MMMM d"
        case .ko: f.dateFormat = "M월 d일 EEEE"
        case .zhHans, .zhHant: f.dateFormat = "M月d日 EEEE"
        }
        return f.string(from: Date())
    }

    private func lockCircleButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(.ultraThinMaterial, in: Circle())
            .environment(\.colorScheme, .dark)
    }
}

/// Renders exact 1:1 replicas of the three LifelogWidgets (systemMedium 364x170pt)
/// using the real widget layout metrics, SF Symbols, rounded fonts, and showcase store data.
struct ASOWidgetShowcaseView: View {
    let store: AppDataStore

    private let widgetWidth: CGFloat = 364
    private let widgetHeight: CGFloat = 170

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.99).ignoresSafeArea()
            VStack(spacing: 28) {
                scheduleMediumWidget
                    .frame(width: widgetWidth, height: widgetHeight)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                habitMediumWidget
                    .frame(width: widgetWidth, height: widgetHeight)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                anniversaryMediumWidget
                    .frame(width: widgetWidth, height: widgetHeight)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .preferredColorScheme(.light)
    }

    private var scheduleMediumWidget: some View {
        let lang = ASOShowcaseLang.current
        let today = Calendar.current.startOfDay(for: Date())
        let cal = Calendar.current
        let month = ScheduleMonth(
            containing: today,
            eventIntervals: store.calendarEvents.compactMap { e in
                e.endDate > e.startDate ? DateInterval(start: e.startDate, end: e.endDate) : nil
            },
            calendar: CalendarWeekStart.sunday.calendar
        )
        let todayEvents = store.events(on: today).prefix(3)
        let todayTask = store.tasks.first(where: { !$0.isCompleted })
        let headerFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: lang.localeIdentifier)
            switch lang {
            case .en: f.dateFormat = "EEE, MMM d"
            case .ko: f.dateFormat = "M월 d일(E)"
            default: f.dateFormat = "M月d日(E)"
            }
            return f
        }()
        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: lang.localeIdentifier)
            f.dateFormat = "H:mm"
            return f
        }()
        let weekdaySymbols = lang.weekdaySymbols

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerFormatter.string(from: today))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(todayEvents.enumerated()), id: \.element.id) { idx, event in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(CategoryPalette.color(for: event.calendarName))
                                .frame(width: 6, height: 6)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(event.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                HStack(spacing: 3) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 8, weight: .semibold))
                                    Text("\(timeFormatter.string(from: event.startDate))-\(timeFormatter.string(from: event.endDate))")
                                        .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                                }
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                        if idx < todayEvents.count - 1 || todayTask != nil {
                            Divider().padding(.leading, 12)
                        }
                    }
                    if let task = todayTask {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "circle")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                            Text(task.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(weekdaySymbols[i])
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(i == 0 ? .red.opacity(0.8) : (i == 6 ? .blue.opacity(0.8) : .primary.opacity(0.85)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 19)

                VStack(spacing: 0) {
                    ForEach(0..<month.weekCount, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { wd in
                                if let d = month.dates[week * 7 + wd] {
                                    let isToday = cal.isDate(d, inSameDayAs: today)
                                    let hasEv = month.daysWithEvents.contains(d)
                                    let dayNum = cal.component(.day, from: d)
                                    let wdNum = cal.component(.weekday, from: d)
                                    VStack(spacing: 0) {
                                        Text("\(dayNum)")
                                            .font(.system(size: 10, weight: isToday ? .bold : .medium, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(isToday ? .white : (wdNum == 1 ? .red.opacity(0.8) : (wdNum == 7 ? .blue.opacity(0.8) : .primary.opacity(0.85))))
                                            .frame(width: 17, height: 17)
                                            .background(isToday ? Circle().fill(Color.accentColor) : nil)
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 3, height: 3)
                                            .opacity(hasEv ? 1 : 0)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    private var habitMediumWidget: some View {
        let lang = ASOShowcaseLang.current
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let weekStart = cal.date(byAdding: .day, value: -(weekday - 1), to: today)!
        let activeHabits = Array(store.habits.prefix(5))
        let dayLabels = lang.weekdaySymbols
        let palette = HabitContributionPalette.colors(for: .light)
        let weeks = 11

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 3) {
                    Spacer().frame(width: 18)
                    ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 14)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(activeHabits) { habit in
                        let tint = Color(hex: habit.colorHex) ?? .accentColor
                        HStack(spacing: 3) {
                            Image(systemName: habit.iconName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tint)
                                .frame(width: 18, height: 18)
                            ForEach(0..<7, id: \.self) { offset in
                                let d = cal.date(byAdding: .day, value: offset, to: weekStart)!
                                let done = store.habitRecords.contains { $0.habitID == habit.id && $0.isCompleted && cal.isDate($0.date, inSameDayAs: d) }
                                ZStack {
                                    Circle()
                                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                                    if done {
                                        Circle().fill(tint)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 14, height: 14)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(spacing: 0) {
                Spacer().frame(height: 20)
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { r in
                                let dayOffset = (w - (weeks - 1)) * 7 + (r - (weekday - 1))
                                let d = cal.date(byAdding: .day, value: dayOffset, to: today)!
                                let isFuture = d > today
                                let isToday = cal.isDate(d, inSameDayAs: today)
                                let completedCount = isFuture ? 0 : store.habitRecords.filter { $0.isCompleted && cal.isDate($0.date, inSameDayAs: d) }.count
                                let level = isFuture ? 0 : min(4, completedCount)
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(palette[level])
                                    .frame(width: 12.5, height: 12.5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2.5)
                                            .stroke(isToday ? Color.black.opacity(0.5) : .clear, lineWidth: isToday ? 1.2 : 0)
                                    )
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(12)
    }

    private var anniversaryMediumWidget: some View {
        let lang = ASOShowcaseLang.current
        let progress: Double = 60.0 / 102.0
        let title = lang.pick("沖縄・夏休み旅行", "Okinawa Beach Trip", "오키나와 여름 여행", "冲绳海岛旅行", "沖繩海島旅行")
        let elapsed = lang.pick("予約した日から 60日経過", "60 days since booked", "예약한 날부터 60일 경과", "预订至今已过 60 天", "預訂至今已過 60 天")
        let prefix = lang.pick("あと", "", "D-", "还剩", "還剩")
        let suffix = lang.pick("日", "days", "일", "天", "天")
        let endLabel = lang.pick("出発まで", "until takeoff", "출발까지", "距出发", "距出發")

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(elapsed)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if !prefix.isEmpty {
                            Text(prefix)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Text("42")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(suffix)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(endLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(Color.orange).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("2026/09/28 → 2027/01/08")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("59%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}
#endif
