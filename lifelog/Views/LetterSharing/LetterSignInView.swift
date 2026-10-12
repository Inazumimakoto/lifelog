//
//  LetterSignInView.swift
//  lifelog
//
//  Sign in with Apple ログイン画面
//

import SwiftUI

/// Sign in with Apple ログイン画面
struct LetterSignInView: View {
    var onSignInComplete: (() -> Void)?

    var body: some View {
        LetterSignInContent(title: "大切な人への手紙",
                            subtitle: "友達と手紙を送り合おう",
                            onSignInComplete: { onSignInComplete?() })
    }
}

#Preview {
    LetterSignInView()
}
