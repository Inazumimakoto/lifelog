//
//  ReviewDetailPanel.swift
//  lifelog
//

import SwiftUI
import UIKit

// MARK: - ReviewDetailPanel
struct ReviewDetailPanel: View {
    let date: Date
    let store: AppDataStore
    let diary: DiaryEntry?
    let isDiaryTextHidden: Bool
    let photoPaths: [String]
    let preferredIndex: Int
    @Binding var reviewPhotoViewerIndex: Int
    @Binding var pendingPhotoViewerDate: Date?
    @Binding var showingDetailPanel: Bool
    let onOpenDiary: (Date) -> Void

    @State private var diaryEditorDate: Date?
    @State private var showPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    @State private var localPhotoIndex: Int = 0

    init(date: Date,
         store: AppDataStore,
         diary: DiaryEntry?,
         isDiaryTextHidden: Bool,
         photoPaths: [String],
         preferredIndex: Int,
         reviewPhotoViewerIndex: Binding<Int>,
         pendingPhotoViewerDate: Binding<Date?>,
         showingDetailPanel: Binding<Bool>,
         onOpenDiary: @escaping (Date) -> Void) {
        self.date = date
        self.store = store
        self.diary = diary
        self.isDiaryTextHidden = isDiaryTextHidden
        self.photoPaths = photoPaths
        self.preferredIndex = preferredIndex
        self._reviewPhotoViewerIndex = reviewPhotoViewerIndex
        self._pendingPhotoViewerDate = pendingPhotoViewerDate
        self._showingDetailPanel = showingDetailPanel
        self.onOpenDiary = onOpenDiary
        _localPhotoIndex = State(initialValue: preferredIndex)
    }

    private func locationLabel(for entry: DiaryEntry) -> String? {
        if let first = entry.locations.first {
            if entry.locations.count > 1 {
                return "\(first.name) ほか\(entry.locations.count - 1)件"
            }
            return first.name
        }
        if let name = entry.locationName, name.isEmpty == false {
            return name
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if photoPaths.isEmpty == false {
                // ScrollView(.horizontal) + scrollTargetBehavior でネストされた TabView を回避
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(photoPaths.enumerated()), id: \.offset) { index, path in
                                DetailPanelPhotoPage(
                                    path: path,
                                    index: index,
                                    onTap: {
                                        // 振り返りの全画面表示は常に「お気に入りの写真」起点にする。
                                        setReviewPhotoSelection(preferredIndex)
                                        showPhotoViewer = true
                                    }
                                )
                                .containerRelativeFrame(.horizontal)
                                .id(index)
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                    .frame(height: 240)
                    .onAppear {
                        setReviewPhotoSelection(preferredIndex)
                        scrollToIndex(selectedPhotoIndex, using: proxy)
                    }
                    .onChange(of: date) { _, _ in
                        setReviewPhotoSelection(preferredIndex)
                        scrollToIndex(selectedPhotoIndex, using: proxy)
                    }
                    .onChange(of: preferredIndex) { _, newValue in
                        setReviewPhotoSelection(newValue)
                        scrollToIndex(selectedPhotoIndex, using: proxy)
                    }
                    .onChange(of: photoPaths) { _, _ in
                        setReviewPhotoSelection(localPhotoIndex)
                        scrollToIndex(selectedPhotoIndex, using: proxy)
                    }
                }
            }
            if let diary {
                if let mood = diary.mood {
                    HStack(spacing: 8) {
                        Text(mood.emoji)
                        Text("気分 \(mood.rawValue)")
                    }
                    .foregroundStyle(.primary)
                }
                if let condition = diary.conditionScore {
                    HStack(spacing: 8) {
                        Text(conditionEmoji(for: condition))
                        Text("体調 \(condition)")
                    }
                    .foregroundStyle(.primary)
                }
                if let place = locationLabel(for: diary) {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .foregroundStyle(.primary)
                }
                if diary.text.isEmpty == false {
                    if isDiaryTextHidden {
                        Text("日記本文は非表示です。")
                            .font(.body)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(diary.text)
                            .font(.body)
                            .lineLimit(1)
                    }
                }
                Button {
                    onOpenDiary(date)
                } label: {
                    Text("この日の日記を開く")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                if isDiaryTextHidden {
                    Text("日記本文は非表示です。")
                        .foregroundStyle(.secondary)
                } else {
                    Text("この日の日記はまだありません。")
                        .foregroundStyle(.secondary)
                }
                Button {
                    onOpenDiary(date)
                } label: {
                    Text("日記を書く")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $diaryEditorDate) { editorDate in
            NavigationStack {
                DiaryEditorView(store: store, date: editorDate)
                    .id(editorDate)
            }
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            DiaryPhotoViewerView(viewModel: DiaryViewModel(store: store, date: date),
                                 initialIndex: reviewPhotoViewerIndex,
                                 onIndexChanged: { newIndex in
                                     selectedPhotoIndex = newIndex
                                     reviewPhotoViewerIndex = newIndex
                                 })
        }
    }

    private func conditionEmoji(for score: Int) -> String {
        switch score {
        case 1: return "😷"
        case 2: return "😓"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "💪"
        default: return "😐"
        }
    }

    private func clampedIndex(_ index: Int) -> Int {
        guard photoPaths.isEmpty == false else { return 0 }
        return min(max(index, 0), photoPaths.count - 1)
    }

    private func setReviewPhotoSelection(_ index: Int) {
        let targetIndex = clampedIndex(index)
        selectedPhotoIndex = targetIndex
        localPhotoIndex = targetIndex
        reviewPhotoViewerIndex = targetIndex
    }

    private func scrollToIndex(_ index: Int, using proxy: ScrollViewProxy) {
        guard photoPaths.indices.contains(index) else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}

// MARK: - Review Day Cell (非同期サムネイル対応)
struct ReviewDayCell: View {
    let day: JournalViewModel.CalendarDay
    let isSelected: Bool
    let showMoodOnReviewCalendar: Bool
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    private var thumbnailPath: String? { day.diary?.favoritePhotoPath ?? day.diary?.photoPaths.first }
    private var hasPhoto: Bool { thumbnail != nil }
    private var moodEmoji: String? { day.diary?.mood?.emoji }
    private var shouldShowMood: Bool { showMoodOnReviewCalendar && moodEmoji != nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background: Photo or empty
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else {
                Color.clear
            }

            // Overlay: Date and mood
            ZStack(alignment: .top) {
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(reviewDateTextColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        hasPhoto ? Color.black.opacity(0.4) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                if shouldShowMood {
                    Text(moodEmoji!)
                        .font(.caption2)
                        .padding(2)
                        .background(
                            hasPhoto ? Color.black.opacity(0.4) : Color.clear,
                            in: Circle()
                        )
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }
            .padding(4)
        }
        .frame(height: 88)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(day.isToday ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .center) {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .opacity(day.isWithinDisplayedMonth ? 1.0 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .task(id: thumbnailPath) {
            guard let path = thumbnailPath else {
                thumbnail = nil
                return
            }
            thumbnail = nil
            thumbnail = await PhotoStorage.loadThumbnail(at: path)
        }
    }

    private var reviewDateTextColor: Color {
        guard hasPhoto == false else { return .white }
        guard day.isWithinDisplayedMonth, Calendar.current.isDateInWeekend(day.date) == false else {
            return .secondary
        }
        return .primary
    }
}
