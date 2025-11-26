//
//  MemoPadViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/15.
//

import Foundation
import Combine

@MainActor
final class MemoPadViewModel: ObservableObject {

    @Published var memoText: String
    @Published private(set) var lastUpdatedAt: Date?

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppDataStore) {
        self.store = store
        let memo = store.memoPad
        self.memoText = memo.text
        self.lastUpdatedAt = memo.lastUpdatedAt
        bind()
    }

    func update(text: String) {
        memoText = text
        store.updateMemoPad(text: text)
        lastUpdatedAt = store.memoPad.lastUpdatedAt
    }

    private func bind() {
        store.$memoPad
            .receive(on: DispatchQueue.main)
            .sink { [weak self] memo in
                guard let self = self else { return }
                if memo.text != self.memoText {
                    self.memoText = memo.text
                }
                self.lastUpdatedAt = memo.lastUpdatedAt
            }
            .store(in: &cancellables)
    }
}
