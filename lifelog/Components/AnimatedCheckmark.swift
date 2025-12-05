//
//  AnimatedCheckmark.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import SwiftUI
import UIKit

/// Apple Store風のアニメーション付きチェックマーク
/// チェック時にストロークアニメーションとハプティックフィードバックを提供
struct AnimatedCheckmark: View {
    let isCompleted: Bool
    let color: Color
    var size: CGFloat = 24
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var circleScale: CGFloat = 0
    @State private var checkmarkProgress: CGFloat = 0
    @State private var bounceScale: CGFloat = 1.0
    
    /// デバイスのカラースキームに応じてチェックマークの色を決定
    private var checkmarkColor: Color {
        // ダークモードなら黒、ライトモードなら白
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        ZStack {
            // 未完了時の空円
            Circle()
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 2)
                .frame(width: size, height: size)
                .opacity(isCompleted ? 0 : 1)
            
            // 完了時の塗りつぶし円
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(circleScale)
                .opacity(isCompleted ? 1 : 0)
            
            // チェックマーク（ストロークアニメーション）
            CheckmarkShape()
                .trim(from: 0, to: checkmarkProgress)
                .stroke(style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                .foregroundStyle(checkmarkColor)
                .frame(width: size * 0.5, height: size * 0.5)
                .opacity(isCompleted ? 1 : 0)
        }
        .scaleEffect(bounceScale)
        .onChange(of: isCompleted) { oldValue, newValue in
            if newValue && !oldValue {
                // チェックされた時のアニメーション
                triggerCompletionAnimation()
            } else if !newValue && oldValue {
                // チェック解除時
                triggerUndoAnimation()
            }
        }
        .onAppear {
            // 初期状態を設定（アニメーションなし）
            if isCompleted {
                circleScale = 1.0
                checkmarkProgress = 1.0
            }
        }
    }
    
    private func triggerCompletionAnimation() {
        // ハプティックフィードバック（成功）
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 円のスケールアニメーション
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            circleScale = 1.0
        }
        
        // チェックマークの描画アニメーション（少し遅延）
        withAnimation(.easeOut(duration: 0.25).delay(0.1)) {
            checkmarkProgress = 1.0
        }
        
        // バウンスエフェクト
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.2)) {
            bounceScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                bounceScale = 1.0
            }
        }
    }
    
    private func triggerUndoAnimation() {
        // 軽いハプティック（リセット）
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        withAnimation(.easeOut(duration: 0.2)) {
            checkmarkProgress = 0
            circleScale = 0
            bounceScale = 1.0
        }
    }
}

/// チェックマークの形状を定義するShape
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // チェックマークの座標（左下から右上へ）
        let startPoint = CGPoint(x: rect.width * 0.15, y: rect.height * 0.5)
        let midPoint = CGPoint(x: rect.width * 0.4, y: rect.height * 0.75)
        let endPoint = CGPoint(x: rect.width * 0.85, y: rect.height * 0.25)
        
        path.move(to: startPoint)
        path.addLine(to: midPoint)
        path.addLine(to: endPoint)
        
        return path
    }
}

#Preview {
    VStack(spacing: 40) {
        HStack(spacing: 30) {
            AnimatedCheckmark(isCompleted: false, color: .blue)
            AnimatedCheckmark(isCompleted: true, color: .blue)
            AnimatedCheckmark(isCompleted: true, color: .green)
            AnimatedCheckmark(isCompleted: true, color: .orange)
        }
        
        // インタラクティブデモ
        AnimatedCheckmarkDemo()
    }
    .padding()
}

private struct AnimatedCheckmarkDemo: View {
    @State private var isCompleted = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("タップしてテスト")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button {
                isCompleted.toggle()
            } label: {
                HStack {
                    Text("習慣サンプル")
                    Spacer()
                    AnimatedCheckmark(isCompleted: isCompleted, color: .purple, size: 28)
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 250)
    }
}
