//
//  FloatingButton.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import SwiftUI

struct FloatingButton: View {
    let iconName: String
    let menuContent: () -> AnyView
    
    init(iconName: String = "plus", @ViewBuilder menuContent: @escaping () -> some View) {
        self.iconName = iconName
        self.menuContent = { AnyView(menuContent()) }
    }
    
    var body: some View {
        Menu {
            menuContent()
        } label: {
            Image(systemName: iconName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 4)
        }
        // パディングは呼び出し元のZStackアラインメントに依存させるため、ここでは最小限に
        // ただしFABとしての安全マージンは持たせる
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

#Preview {
    ZStack(alignment: .bottomTrailing) {
        Color.gray.opacity(0.1).ignoresSafeArea()
        FloatingButton {
            Button("Action 1") {}
            Button("Action 2") {}
        }
    }
}
