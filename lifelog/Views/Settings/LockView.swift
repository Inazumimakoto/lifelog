//
//  LockView.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import SwiftUI

struct LockView: View {
    @ObservedObject var appLockService = AppLockService.shared
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text("lifelogはロックされています")
                    .font(.headline)
                
                Button {
                    appLockService.authenticate()
                } label: {
                    Text("ロックを解除")
                        .font(.headline)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                }
                .padding(.top, 20)
            }
        }
    }
}

#Preview {
    LockView()
}
