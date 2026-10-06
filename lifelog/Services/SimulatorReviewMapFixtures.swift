import Foundation

#if DEBUG && targetEnvironment(simulator)
/// Deterministic map fixtures, generated separately from the isolated demo store's save path.
/// See docs/requirements.md §4.11 and docs/ui-guidelines.md §Diary.
enum SimulatorReviewMapFixtures {
    static let placeCount = 1_000

    static func entries(referenceDate: Date, calendar: Calendar = .current) -> [DiaryEntry] {
        let today = calendar.startOfDay(for: referenceDate)
        let dates = (0..<6).map { calendar.date(byAdding: .day, value: $0 - 5, to: today)! }
        var locationsByDay = Array(repeating: [DiaryLocation](), count: dates.count)

        for index in 0..<placeCount {
            let coordinate = coordinate(for: index)
            for dayIndex in recordedDayIndices(for: index) {
                locationsByDay[dayIndex].append(DiaryLocation(
                    id: identifier(namespace: "DE200000", index: index + 1),
                    name: String(localized: "サンプルスポット \(index + 1)"),
                    address: nil,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    mapItemURL: nil,
                    photoPaths: [],
                    visitTags: tags(for: index, dayIndex: dayIndex)
                ))
            }
        }

        return dates.enumerated().map { dayIndex, date in
            DiaryEntry(
                id: identifier(namespace: "DE100000", index: dayIndex + 1),
                date: date,
                text: String(localized: "訪れた場所やタグを振り返るためのサンプル日記です。"),
                mood: .neutral,
                conditionScore: 3,
                locations: locationsByDay[dayIndex],
                photoPaths: [],
                locationPhotoPaths: []
            )
        }
    }

    private static func recordedDayIndices(for index: Int) -> [Int] {
        switch index % 3 {
        case 0:
            return [(index / 3) % 6]
        case 1:
            return (index / 3).isMultiple(of: 2) ? [0, 2, 4] : [1, 3, 5]
        default:
            return Array(0..<6)
        }
    }

    private static func tags(for index: Int, dayIndex: Int) -> [String] {
        // Keep untagged examples stable across every day for gray points and filter checks.
        guard !index.isMultiple(of: 10) else { return [] }
        let tagNames = ["ご飯", "カフェ", "仕事", "勉強", "買い物", "旅行", "観光", "運動", "用事", "友人", "家族", "デート"]
        let available = index % 3 == 2 ? Array(tagNames.prefix(9)) : tagNames
        let count = 1 + (index + dayIndex) % 8
        let start = index % 3 == 2 ? dayIndex : index + dayIndex
        return (0..<count).map { available[(start + $0) % available.count] }
    }

    private static func coordinate(for index: Int) -> (latitude: Double, longitude: Double) {
        let cityIndex = index % cityAnchors.count
        let localIndex = index / cityAnchors.count
        let anchor = cityAnchors[cityIndex]

        // Seven Tokyo points sit about 20–70 m apart for date-label collision checks.
        if cityIndex == 12, localIndex < tokyoNearbyCoordinates.count {
            return tokyoNearbyCoordinates[localIndex]
        }
        // Small, deterministic offsets retain city clusters without scattering coastal points offshore.
        let angle = Double(localIndex) * 137.507764 * .pi / 180
        let radius = 180 + Double(localIndex) * 35
        let north = cos(angle) * radius
        let east = sin(angle) * radius
        let latitude = anchor.latitude + north / 111_320
        let longitude = anchor.longitude + east / (111_320 * cos(anchor.latitude * .pi / 180))
        return (latitude, longitude)
    }

    private static func identifier(namespace: String, index: Int) -> UUID {
        UUID(uuidString: String(format: "\(namespace)-0000-4000-8000-%012d", index))!
    }

    private static let tokyoNearbyCoordinates: [(latitude: Double, longitude: Double)] = [
        (35.681236, 139.767125),
        (35.681420, 139.767180),
        (35.681115, 139.767310),
        (35.680870, 139.766680),
        (35.681655, 139.767385),
        (35.681415, 139.766600),
        (35.681045, 139.767820)
    ]

    // One urban anchor per prefecture, ordered north to south; coastal anchors are set inland.
    private static let cityAnchors: [(latitude: Double, longitude: Double)] = [
        (43.0618, 141.3545), // Sapporo
        (40.8100, 140.7400), // Aomori
        (39.7036, 141.1527), // Morioka
        (38.2682, 140.8694), // Sendai
        (39.7199, 140.1035), // Akita
        (38.2405, 140.3633), // Yamagata
        (37.7608, 140.4747), // Fukushima
        (36.3659, 140.4712), // Mito
        (36.5551, 139.8826), // Utsunomiya
        (36.3895, 139.0634), // Maebashi
        (35.8617, 139.6455), // Saitama
        (35.6074, 140.1065), // Chiba
        (35.681236, 139.767125), // Tokyo
        (35.4558, 139.6147), // Yokohama
        (37.9120, 139.0610), // Niigata
        (36.6953, 137.2113), // Toyama
        (36.5613, 136.6562), // Kanazawa
        (36.0652, 136.2216), // Fukui
        (35.6639, 138.5684), // Kofu
        (36.6486, 138.1948), // Nagano
        (35.4233, 136.7607), // Gifu
        (34.9756, 138.3828), // Shizuoka
        (35.1815, 136.9066), // Nagoya
        (34.7186, 136.4960), // Tsu
        (35.0069, 135.8551), // Otsu
        (35.0116, 135.7681), // Kyoto
        (34.6937, 135.5023), // Osaka
        (34.7000, 135.1910), // Kobe
        (34.6851, 135.8048), // Nara
        (34.2305, 135.1708), // Wakayama
        (35.5011, 134.2351), // Tottori
        (35.4740, 133.0660), // Matsue
        (34.6551, 133.9195), // Okayama
        (34.4000, 132.4600), // Hiroshima
        (34.1859, 131.4714), // Yamaguchi
        (34.0703, 134.5548), // Tokushima
        (34.3300, 134.0440), // Takamatsu
        (33.8392, 132.7656), // Matsuyama
        (33.5597, 133.5311), // Kochi
        (33.5902, 130.4017), // Fukuoka
        (33.2635, 130.3009), // Saga
        (32.7680, 129.8750), // Nagasaki
        (32.8031, 130.7079), // Kumamoto
        (33.2382, 131.6126), // Oita
        (31.9111, 131.4239), // Miyazaki
        (31.5966, 130.5571), // Kagoshima
        (26.2200, 127.6900)  // Naha
    ]
}
#endif
