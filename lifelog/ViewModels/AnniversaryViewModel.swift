//
//  AnniversaryViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine

@MainActor
final class AnniversaryViewModel: ObservableObject {

    struct Row: Identifiable {
        let anniversary: Anniversary
        let relativeText: String

        var id: UUID { anniversary.id }
    }

    @Published private(set) var rows: [Row] = []

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppDataStore) {
        self.store = store
        bind()
        refresh()
    }

    private func bind() {
        store.$anniversaries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        let today = Date()
        rows = store.anniversaries.map { anniversary in
            let relative = anniversary.daysRelative(to: today)
            let text: String
            switch relative {
            case 0: text = "今日"
            case let days where days > 0: text = "まで\(days)日"
            default: text = "から\(abs(relative))日"
            }
            return Row(anniversary: anniversary, relativeText: text)
        }.sorted(by: { $0.anniversary.targetDate < $1.anniversary.targetDate })
    }

    func addAnniversary(title: String,
                        targetDate: Date,
                        type: AnniversaryType,
                        repeatsYearly: Bool) {
        let newValue = Anniversary(title: title, targetDate: targetDate, type: type, repeatsYearly: repeatsYearly)
        store.addAnniversary(newValue)
    }

    func add(_ anniversary: Anniversary) {
        store.addAnniversary(anniversary)
    }

    func update(_ anniversary: Anniversary) {
        store.updateAnniversary(anniversary)
    }
}
