//
//  CalendarCategorySettingsView.swift
//  lifelog
//

import SwiftUI
import EventKit

struct CalendarCategorySettingsView: View {
    @ObservedObject var store: AppDataStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var calendarService = CalendarEventService()
    @State private var selection: CalendarCategoryLink?
    @State private var authorization = EKEventStore.authorizationStatus(for: .event)
    @State private var isRefreshing = false
    @State private var refreshAgain = false
    @State private var refreshFailed = false
    @State private var refreshTrigger = 0

    // docs/requirements.md §4.9: display the persisted mapping directly so a
    // shared category rename cannot be overwritten by an old screen snapshot.
    private var links: [CalendarCategoryLink] {
        store.appState.calendarCategoryLinks.sorted {
            $0.calendarTitle.localizedStandardCompare($1.calendarTitle) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                Text("calendar.integration.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            if authorization == .fullAccess {
                calendarSections
            } else {
                permissionSection
            }

            if refreshFailed {
                Section {
                    Label("calendar.integration.refreshFailed", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("カレンダー連携")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isRefreshing {
                    ProgressView()
                        .accessibilityLabel(Text("calendar.integration.refreshing"))
                } else if authorization == .fullAccess {
                    Button {
                        refreshTrigger += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(Text("calendar.integration.refresh"))
                }
            }
        }
        .sheet(item: $selection) { link in
            // Closing the picker leaves the current mapping intact. Read the
            // current value even when another calendar shares this category.
            CategorySelectionView(selectedCategory: Binding(
                get: {
                    store.appState.calendarCategoryLinks.first {
                        $0.calendarIdentifier == link.calendarIdentifier
                    }?.categoryId ?? ""
                },
                set: { newValue in
                    let category = newValue.isEmpty ? nil : newValue
                    store.updateCalendarLinkCategory(calendarIdentifier: link.calendarIdentifier,
                                                     categoryName: category)
                    refreshTrigger += 1
                }
            ), noneLabel: String(localized: "表示しない"))
            .environmentObject(store)
        }
        .task(id: refreshTrigger) {
            await refreshCalendars()
        }
        .refreshable {
            await refreshCalendars()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshTrigger += 1
            }
        }
    }

    @ViewBuilder
    private var calendarSections: some View {
        if links.isEmpty {
            Section {
                ContentUnavailableView("calendar.integration.empty.title", systemImage: "calendar",
                                       description: Text("calendar.integration.empty.description"))
            }
        } else {
            let visible = links.filter { $0.categoryId != nil }
            let hidden = links.filter { $0.categoryId == nil }
            if !visible.isEmpty {
                Section {
                    ForEach(visible) { link in
                        calendarRow(link)
                    }
                } header: {
                    Text("calendar.integration.visible")
                } footer: {
                    Text("calendar.integration.colorExplanation")
                }
            }
            if !hidden.isEmpty {
                Section("calendar.integration.hidden") {
                    ForEach(hidden) { link in
                        calendarRow(link)
                    }
                }
            }
        }
    }

    private func calendarRow(_ link: CalendarCategoryLink) -> some View {
        Button {
            selection = link
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(link.colorHex.flatMap { Color(hex: $0) } ?? .secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(link.calendarTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if let category = link.categoryId {
                            Text("calendar.integration.destination")
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(CategoryPalette.color(for: category))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(CategoryPalette.displayName(for: category))
                                .foregroundStyle(.primary)
                        } else {
                            Image(systemName: "eye.slash")
                                .accessibilityHidden(true)
                            Text("表示しない")
                        }
                    }
                    .font(.subheadline)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("calendar.integration.chooseCategory"))
    }

    private var permissionSection: some View {
        Section {
            Label("calendar.integration.permission.title", systemImage: "calendar.badge.exclamationmark")
                .font(.headline)
            Text("calendar.integration.permission.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if authorization == .notDetermined {
                Button("calendar.integration.allowAccess") {
                    _Concurrency.Task {
                        await refreshCalendars(shouldPrompt: true)
                    }
                }
                .disabled(isRefreshing)
            } else if authorization != .restricted {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
    }

    private func refreshCalendars(shouldPrompt: Bool = false) async {
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        refreshFailed = false
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            let granted = await calendarService.requestAccessIfNeeded(shouldPrompt: shouldPrompt)
            authorization = EKEventStore.authorizationStatus(for: .event)
            guard granted else { return }
            refreshFailed = !(await store.syncExternalCalendarsIfAuthorized())
        } while refreshAgain
    }
}
