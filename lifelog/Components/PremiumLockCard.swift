//
//  PremiumLockCard.swift
//  lifelog
//
//  Created by Codex on 2026/02/06.
//

import SwiftUI

struct PremiumLockCard: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.yellow)
                Text(title)
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
