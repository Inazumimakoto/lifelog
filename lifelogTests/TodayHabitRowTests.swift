import SwiftUI
import UIKit
import XCTest
@testable import lifelify

@MainActor
final class TodayHabitRowTests: XCTestCase {
    func testStreakVisibilityAndDigits_keepSingleLineHeightAcrossLanguagesAndTextSizes() throws {
        for language in ["ja", "en", "ko", "zh-Hans", "zh-Hant"] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let sizes = try [0, 1, 14, 999].map { count in
                    try render(TodayHabitRow(status: status(streak: count))
                        .environment(\.locale, Locale(identifier: language))
                        .environment(\.dynamicTypeSize, textSize)
                        .frame(width: 320)).size
                }
                for size in sizes {
                    XCTAssertEqual(size.width, 320, accuracy: 0.5)
                    XCTAssertEqual(size.height, sizes[0].height, accuracy: 0.5,
                                   "\(language), \(textSize): streak must not add another line")
                }
            }
        }
    }

    func testRowExamples_renderForAlignmentReview() throws {
        for (language, textSize) in [("ja", DynamicTypeSize.large), ("en", .large), ("en", .accessibility3)] {
            let content = VStack(spacing: 12) {
                ForEach([0, 1, 14, 999], id: \.self) { count in
                    TodayHabitRow(status: self.status(streak: count))
                }
                TodayHabitRow(status: status(streak: 14, longTitle: true))
            }
            .padding(16)
            .frame(width: 352)
            .environment(\.locale, Locale(identifier: language))
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.colorScheme, .light)
            .background(Color.white)
            let attachment = XCTAttachment(image: try render(content))
            attachment.name = "Home habit rows - \(language) - \(textSize)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func status(streak: Int, longTitle: Bool = false) -> TodayViewModel.DailyHabitStatus {
        let title = longTitle ? "A very long habit name that should stay on a single line" : "Reading"
        return .init(habit: Habit(title: title, iconName: "book", colorHex: "#3478F6", schedule: .daily),
                     record: nil, currentStreak: streak)
    }

    private func render(_ content: some View) throws -> UIImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage)
    }
}
