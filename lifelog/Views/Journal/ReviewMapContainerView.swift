import SwiftUI

/// Isolates the map from JournalView's broad AppDataStore observation.
struct ReviewMapContainerView: View, Equatable {
    let store: AppDataStore
    @Binding var period: ReviewMapPeriod
    let anchorDate: Date
    let onOpenDiary: (Date) -> Void
    private let periodValue: ReviewMapPeriod
    @StateObject private var viewModel: ReviewMapViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(store: AppDataStore, period: Binding<ReviewMapPeriod>, anchorDate: Date,
         onOpenDiary: @escaping (Date) -> Void) {
        self.store = store
        _period = period
        periodValue = period.wrappedValue
        self.anchorDate = anchorDate
        self.onOpenDiary = onOpenDiary
        _viewModel = StateObject(wrappedValue: ReviewMapViewModel(store: store))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.store === rhs.store && lhs.periodValue == rhs.periodValue && lhs.anchorDate == rhs.anchorDate
    }

    var body: some View {
        Group {
            if let state = viewModel.displayState {
                ReviewMapView(snapshot: state.snapshot, renderedPlaces: state.renderedPlaces,
                              tagDefinitions: viewModel.tagDefinitions, period: $period,
                              onFiltersChanged: viewModel.setFilters,
                              onOpenDiary: onOpenDiary)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 420)
            }
        }
        .onAppear { viewModel.activate(period: period, anchorDate: anchorDate) }
        .onChange(of: period) { _, value in viewModel.setPeriod(value, anchorDate: anchorDate) }
        .onChange(of: anchorDate) { _, value in viewModel.setPeriod(period, anchorDate: value) }
        .onChange(of: scenePhase) { _, value in
            if value == .active {
                viewModel.refreshEnvironment()
            } else if value == .background {
                _Concurrency.Task { await viewModel.flush() }
            }
        }
        .onDisappear {
            _Concurrency.Task { await viewModel.flush() }
        }
    }
}
