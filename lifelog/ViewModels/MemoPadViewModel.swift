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

    @Published private(set) var memoPad: MemoPad

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppDataStore) {
        self.store = store
        self.memoPad = store.memoPad
        bind()
    }

    func update(text: String) {
        store.updateMemoPad(text: text)
    }

    private func bind() {
        store.$memoPad
            .receive(on: DispatchQueue.main)
            .sink { [weak self] memo in
                self?.memoPad = memo
            }
            .store(in: &cancellables)
    }
}
