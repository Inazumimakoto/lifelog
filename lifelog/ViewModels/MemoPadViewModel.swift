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

    @Published private(set) var memoText: String
    @Published private(set) var lastUpdatedAt: Date?

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()
    private var pendingText: String
    private var textPersistTask: _Concurrency.Task<Void, Never>?
    private static let textDebounceInterval: TimeInterval = 0.8

    init(store: AppDataStore) {
        self.store = store
        let memo = store.memoPad
        self.memoText = memo.text
        self.pendingText = memo.text
        self.lastUpdatedAt = memo.lastUpdatedAt
        bind()
    }

    var textDraft: String {
        pendingText
    }

    func update(text: String) {
        guard pendingText != text else { return }
        pendingText = text
        debouncedPersistText()
    }

    func flushPendingSave() {
        textPersistTask?.cancel()
        textPersistTask = nil
        persistText(syncSwiftData: true)
    }

    private func debouncedPersistText() {
        textPersistTask?.cancel()
        textPersistTask = _Concurrency.Task { [weak self] in
            do {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(Self.textDebounceInterval * 1_000_000_000))
                guard !_Concurrency.Task.isCancelled else { return }
                await self?.persistText(syncSwiftData: false)
            } catch {
                // Task.sleep がキャンセルされた場合（正常動作）
            }
        }
    }

    private func persistText(syncSwiftData: Bool) {
        store.updateMemoPad(text: pendingText, syncSwiftData: syncSwiftData)
        guard syncSwiftData else { return }
        memoText = pendingText
        lastUpdatedAt = store.memoPad.lastUpdatedAt
    }

    private func bind() {
        store.$memoPad
            .receive(on: DispatchQueue.main)
            .sink { [weak self] memo in
                guard let self = self else { return }
                if memo.text != self.pendingText {
                    self.pendingText = memo.text
                    self.memoText = memo.text
                } else if memo.text != self.memoText {
                    self.memoText = memo.text
                }
                self.lastUpdatedAt = memo.lastUpdatedAt
            }
            .store(in: &cancellables)
    }
}
