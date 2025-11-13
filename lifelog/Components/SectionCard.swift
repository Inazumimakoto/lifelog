//
//  SectionCard.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct SectionCard<Content: View>: View {
    var title: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var content: () -> Content

    init(title: String? = nil,
         actionTitle: String? = nil,
         action: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || actionTitle != nil {
                HStack {
                    if let title {
                        Text(title)
                            .font(.headline)
                    }
                    Spacer()
                    if let actionTitle {
                        Button(actionTitle, action: { action?() })
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            content()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

