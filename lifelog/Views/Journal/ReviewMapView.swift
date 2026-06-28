//
//  ReviewMapView.swift
//  lifelog
//

import SwiftUI
import UIKit
import MapKit

enum ReviewMapPeriod: String, CaseIterable, Identifiable {
    case month = "今月"
    case all = "すべて"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .month: return String(localized: "今月")
        case .all: return String(localized: "すべて")
        }
    }
}

struct ReviewMapPlaceDetailSheet: View {
    let group: ReviewLocationGroup
    let onOpenDiary: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text(group.name)
                    .font(.headline)
                if let address = group.address, address.isEmpty == false {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if group.count > 1 {
                    Text("\(group.count)回")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(group.visits) { visit in
                        ReviewMapVisitRow(visit: visit, onOpenDiary: onOpenDiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ReviewMapVisitRow: View {
    let visit: ReviewLocationVisit
    let onOpenDiary: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPhotoViewer = false
    @State private var photoViewerIndex = 0

    private let photoSize: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if visit.tags.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(visit.tags, id: \.self) { tag in
                            Text(BuiltInDisplayName.locationVisitTag(tag))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                    }
                }
            }
            if visit.photoPaths.isEmpty {
                Text("写真なし")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(visit.photoPaths.enumerated()), id: \.offset) { index, path in
                            Button {
                                photoViewerIndex = index
                                showPhotoViewer = true
                            } label: {
                                AsyncThumbnailImage(path: path, size: photoSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button {
                onOpenDiary(visit.date)
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Text(visit.date.jaMonthDayString)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .fullScreenCover(isPresented: $showPhotoViewer) {
            ReviewMapPhotoViewer(paths: visit.photoPaths, initialIndex: photoViewerIndex)
        }
    }
}

struct ReviewMapPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let paths: [String]
    @State private var currentIndex: Int
    @State private var chromeVisible = true
    @State private var verticalDragOffset: CGFloat = 0
    @State private var isCurrentPhotoZoomed = false
    private let dismissDragThreshold: CGFloat = 140

    init(paths: [String], initialIndex: Int) {
        self.paths = paths
        let clampedIndex = max(0, min(initialIndex, max(0, paths.count - 1)))
        _currentIndex = State(initialValue: clampedIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            ZStack {
                if paths.isEmpty == false {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                            ReviewMapFullImagePage(path: path,
                                                   chromeVisible: $chromeVisible,
                                                   isZoomed: zoomStateBinding(for: index))
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .background(PagingTabViewScrollControl(isScrollEnabled: isCurrentPhotoZoomed == false))
                }

                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        Spacer()
                    }
                    .padding([.top, .horizontal], 16)
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(chromeVisible)
                    Spacer()
                }
            }
            .offset(y: verticalDragOffset)
        }
        .simultaneousGesture(verticalDismissGesture)
        .onChange(of: currentIndex) { _, _ in
            isCurrentPhotoZoomed = false
        }
    }

    private var backgroundOpacity: Double {
        let progress = min(max(verticalDragOffset / dismissDragThreshold, 0), 1)
        return 1 - (progress * 0.45)
    }

    private var verticalDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard isCurrentPhotoZoomed == false else { return }
                let vertical = value.translation.height
                let horizontal = value.translation.width
                guard vertical > 0, abs(vertical) > abs(horizontal) else { return }
                verticalDragOffset = min(vertical, 360)
            }
            .onEnded { value in
                guard isCurrentPhotoZoomed == false else {
                    resetVerticalDragOffset()
                    return
                }
                let vertical = value.translation.height
                let horizontal = value.translation.width

                guard vertical > 0, abs(vertical) > abs(horizontal) else {
                    resetVerticalDragOffset()
                    return
                }

                if vertical >= dismissDragThreshold {
                    dismiss()
                } else {
                    resetVerticalDragOffset()
                }
            }
    }

    private func resetVerticalDragOffset() {
        guard verticalDragOffset != 0 else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            verticalDragOffset = 0
        }
    }

    private func zoomStateBinding(for index: Int) -> Binding<Bool> {
        Binding(get: {
            currentIndex == index ? isCurrentPhotoZoomed : false
        }, set: { newValue in
            guard currentIndex == index else { return }
            isCurrentPhotoZoomed = newValue
        })
    }
}

struct ReviewMapFullImagePage: View {
    let path: String
    @Binding var chromeVisible: Bool
    @Binding var isZoomed: Bool

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                ZoomableImageScrollView(image: image, isZoomed: $isZoomed) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        chromeVisible.toggle()
                    }
                }
                .id(path)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Color.black
            }
        }
        .background(Color.black)
        .onDisappear {
            isZoomed = false
        }
        .task(id: path) {
            image = nil
            isLoading = true
            isZoomed = false
            image = await PhotoStorage.loadFullImage(at: path)
            isLoading = false
        }
    }
}

struct ReviewMapView: View {
    let groups: [ReviewLocationGroup]
    let orderedTags: [String]
    @Binding var period: ReviewMapPeriod
    let onOpenDiary: (Date) -> Void

    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var selectedGroup: ReviewLocationGroup?
    @State private var detailGroup: ReviewLocationGroup?
    @State private var fullScreenSelectedGroup: ReviewLocationGroup?
    @State private var fullScreenDetailGroup: ReviewLocationGroup?
    @State private var hasAppliedRegion = false
    @State private var selectedTagFilters: [String] = []
    @State private var showTagFilterSheet = false
    @State private var showFullScreenTagFilterSheet = false
    @State private var showFullScreenMap = false

    private static let defaultRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.2048, longitude: 138.2529),
                                                          span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12))
    private static let untaggedFilterToken = "__untagged__"
    private static let untaggedFilterLabel = "未タグ"

    var body: some View {
        VStack(spacing: 12) {
            mapCanvas(selection: $selectedGroup,
                      showsExpandButton: true,
                      showsEmptyOverlay: false,
                      onFilterTap: { showTagFilterSheet = true })
            .onChange(of: selectedGroup) { _, newValue in
                guard let group = newValue else { return }
                detailGroup = group
                selectedGroup = nil
            }
            .onAppear {
                applyRegion(force: true)
            }
            .onChange(of: period) { _, _ in
                applyRegion(force: true)
            }
            .onChange(of: groups) { _, _ in
                applyRegion(force: true)
            }
            .onChange(of: selectedTagFilters) { _, _ in
                applyRegion(force: true)
            }

            if filteredGroups.isEmpty {
                emptyState
            } else {
                listSheet
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $detailGroup) { group in
            ReviewMapPlaceDetailSheet(group: group, onOpenDiary: { date in
                onOpenDiary(date)
                detailGroup = nil
            })
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTagFilterSheet) {
            ReviewMapTagFilterSheet(tags: availableFilterTags,
                                    selectedFilters: $selectedTagFilters,
                                    untaggedToken: Self.untaggedFilterToken,
                                    untaggedLabel: Self.untaggedFilterLabel)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showFullScreenMap) {
            fullScreenMap
        }
    }

    private func mapCanvas(selection: Binding<ReviewLocationGroup?>,
                           showsExpandButton: Bool,
                           showsEmptyOverlay: Bool,
                           onFilterTap: @escaping () -> Void) -> some View {
        Map(position: $cameraPosition,
            interactionModes: .all,
            selection: selection) {
            ForEach(filteredGroups) { group in
                Annotation(group.name, coordinate: group.coordinate) {
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Text(group.dateSummary)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.black.opacity(0.7), in: Capsule())
                                .lineLimit(1)
                        }
                        .padding(.bottom, -5)
                        .zIndex(1)
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .zIndex(0)
                    }
                }
                .tag(group)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay(alignment: .topTrailing) {
            periodMenu
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        .overlay(alignment: .topLeading) {
            tagFilterOverlay(onTap: onFilterTap)
                .padding(.top, 8)
                .padding(.leading, 12)
        }
        .overlay(alignment: .bottomTrailing) {
            if showsExpandButton {
                expandMapButton
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .bottom) {
            if showsEmptyOverlay && filteredGroups.isEmpty {
                emptyState
                    .padding(.bottom, 16)
            }
        }
        .frame(minHeight: 420)
    }

    private var fullScreenMap: some View {
        NavigationStack {
            mapCanvas(selection: $fullScreenSelectedGroup,
                      showsExpandButton: false,
                      showsEmptyOverlay: true,
                      onFilterTap: { showFullScreenTagFilterSheet = true })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("振り返り地図")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        showFullScreenMap = false
                    }
                }
            }
        }
        .onChange(of: fullScreenSelectedGroup) { _, newValue in
            guard let group = newValue else { return }
            fullScreenDetailGroup = group
            fullScreenSelectedGroup = nil
        }
        .onDisappear {
            fullScreenSelectedGroup = nil
            fullScreenDetailGroup = nil
            showFullScreenTagFilterSheet = false
        }
        .sheet(item: $fullScreenDetailGroup) { group in
            ReviewMapPlaceDetailSheet(group: group, onOpenDiary: openDiaryFromFullScreenMap)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFullScreenTagFilterSheet) {
            ReviewMapTagFilterSheet(tags: availableFilterTags,
                                    selectedFilters: $selectedTagFilters,
                                    untaggedToken: Self.untaggedFilterToken,
                                    untaggedLabel: Self.untaggedFilterLabel)
                .presentationDetents([.medium, .large])
        }
    }

    private var expandMapButton: some View {
        Button {
            showFullScreenMap = true
        } label: {
            Label("全画面", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("地図を全画面表示")
    }

    private var periodMenu: some View {
        Menu {
            ForEach(ReviewMapPeriod.allCases) { option in
                Button(option.displayName) {
                    period = option
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(period.displayName)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func tagFilterOverlay(onTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onTap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedTagFilters.isEmpty ? "絞り込み" : "タグ \(selectedTagFilters.count)")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if selectedTagFilters.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedFilterLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        Button("クリア") {
                            selectedTagFilters = []
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .frame(maxWidth: 260)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(emptyStateMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
    }

    private var listSheet: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredGroups) { group in
                        Button {
                            detailGroup = group
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(group.dateSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if group.allTags.isEmpty == false {
                                        Text(group.allTags.prefix(3).joined(separator: " / "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 220)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
    }

    private func applyRegion(force: Bool) {
        guard force || hasAppliedRegion == false else { return }
        let region = regionForEntries(filteredGroups)
        cameraPosition = .region(region)
        hasAppliedRegion = true
    }

    private var filteredGroups: [ReviewLocationGroup] {
        guard selectedTagFilters.isEmpty == false else {
            return groups
        }
        return groups.compactMap { group in
            let matchedVisits = group.visits.filter(visitMatchesFilter)
            guard matchedVisits.isEmpty == false else { return nil }
            return ReviewLocationGroup(id: group.id, location: group.location, visits: matchedVisits)
        }
    }

    private var availableFilterTags: [String] {
        var seen: Set<String> = []
        var merged: [String] = []
        func append(_ name: String) {
            let key = normalizedTagKey(name)
            guard seen.contains(key) == false else { return }
            seen.insert(key)
            merged.append(name)
        }
        for tag in orderedTags {
            append(tag)
        }
        for group in groups {
            for tag in group.allTags {
                append(tag)
            }
        }
        return merged
    }

    private var selectedFilterLabels: [String] {
        selectedTagFilters.map { $0 == Self.untaggedFilterToken ? Self.untaggedFilterLabel : $0 }
    }

    private var emptyStateMessage: String {
        if groups.isEmpty {
            return "この期間の場所はありません"
        }
        return "選択中タグに一致する場所はありません"
    }

    private func visitMatchesFilter(_ visit: ReviewLocationVisit) -> Bool {
        guard selectedTagFilters.isEmpty == false else { return true }
        let includesUntagged = selectedTagFilters.contains(Self.untaggedFilterToken)
        if includesUntagged && visit.tags.isEmpty {
            return true
        }
        let selectedKeys = Set(selectedTagFilters
            .filter { $0 != Self.untaggedFilterToken }
            .map(normalizedTagKey))
        guard selectedKeys.isEmpty == false else { return false }
        return visit.tags.contains { selectedKeys.contains(normalizedTagKey($0)) }
    }

    private func normalizedTagKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func regionForEntries(_ items: [ReviewLocationGroup]) -> MKCoordinateRegion {
        guard let first = items.first else { return Self.defaultRegion }
        var minLat = first.coordinate.latitude
        var maxLat = first.coordinate.latitude
        var minLon = first.coordinate.longitude
        var maxLon = first.coordinate.longitude
        for entry in items.dropFirst() {
            minLat = min(minLat, entry.coordinate.latitude)
            maxLat = max(maxLat, entry.coordinate.latitude)
            minLon = min(minLon, entry.coordinate.longitude)
            maxLon = max(maxLon, entry.coordinate.longitude)
        }
        let latDelta = max(0.05, (maxLat - minLat) * 1.4)
        let lonDelta = max(0.05, (maxLon - minLon) * 1.4)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: latDelta,
                                                         longitudeDelta: lonDelta))
    }

    private func openDiaryFromFullScreenMap(_ date: Date) {
        fullScreenDetailGroup = nil
        showFullScreenMap = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onOpenDiary(date)
        }
    }
}

struct ReviewMapTagFilterSheet: View {
    let tags: [String]
    @Binding var selectedFilters: [String]
    let untaggedToken: String
    let untaggedLabel: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("複数選択時は OR 条件（どれか一致）で絞り込みます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("タグ") {
                    filterRow(label: untaggedLabel, token: untaggedToken)
                    ForEach(tags, id: \.self) { tag in
                        filterRow(label: tag, token: tag)
                    }
                }
            }
            .navigationTitle("地図タグ絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("クリア") {
                        selectedFilters = []
                    }
                    .disabled(selectedFilters.isEmpty)
                }
            }
        }
    }

    private func filterRow(label: String, token: String) -> some View {
        Button {
            toggle(token)
        } label: {
            HStack {
                Text(label)
                Spacer()
                if contains(token) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func contains(_ token: String) -> Bool {
        if token == untaggedToken {
            return selectedFilters.contains(untaggedToken)
        }
        let key = normalizedTagKey(token)
        return selectedFilters.contains {
            $0 != untaggedToken && normalizedTagKey($0) == key
        }
    }

    private func toggle(_ token: String) {
        if token == untaggedToken {
            if let index = selectedFilters.firstIndex(of: untaggedToken) {
                selectedFilters.remove(at: index)
            } else {
                selectedFilters.append(untaggedToken)
            }
            return
        }

        let key = normalizedTagKey(token)
        if let index = selectedFilters.firstIndex(where: {
            $0 != untaggedToken && normalizedTagKey($0) == key
        }) {
            selectedFilters.remove(at: index)
        } else {
            selectedFilters.append(token)
        }
    }

    private func normalizedTagKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
