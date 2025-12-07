//
//  LetterOpeningView.swift
//  lifelog
//
//  Created by AI for Letter to the Future feature
//

import SwiftUI
import UIKit

struct LetterOpeningView: View {
    let letter: Letter
    var onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var tearProgress: CGFloat = 0
    @State private var isOpened = false
    @State private var envelopeScale: CGFloat = 1
    @State private var envelopeOpacity: Double = 1
    @State private var letterPaperOffset: CGFloat = 0
    @State private var letterPaperOpacity: Double = 0
    @State private var showFullContent = false
    @State private var fullContentOpacity: Double = 0
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    @State private var isVisible = false
    
    var body: some View {
        ZStack {
            // 背景
            Color(uiColor: UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1))
                .ignoresSafeArea()
            
            if isVisible {
                VStack {
                    // 閉じるボタン
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding()
                    }
                    
                    Spacer()
                    
                    if showFullContent {
                        // 開封後: 手紙の全文表示
                        fullLetterContent
                            .opacity(fullContentOpacity)
                    } else {
                        // 封筒と手紙のアニメーション
                        ZStack {
                            // 手紙（封筒の後ろから出てくる）
                            letterPaper
                                .offset(y: letterPaperOffset)
                                .opacity(letterPaperOpacity)
                            
                            // 封筒
                            envelopeView
                                .scaleEffect(envelopeScale)
                                .opacity(envelopeOpacity)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeIn(duration: 0.2)) {
                    isVisible = true
                }
            }
        }
    }
    
    // MARK: - 封筒ビュー
    
    private var envelopeView: some View {
        VStack(spacing: 20) {
            Text("📨 過去のあなたから手紙が届きました")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(letter.createdAt.jaFullDateString)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            // 封筒本体
            ZStack {
                // 封筒本体
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: UIColor(red: 0.96, green: 0.90, blue: 0.83, alpha: 1)),
                                     Color(uiColor: UIColor(red: 0.91, green: 0.84, blue: 0.77, alpha: 1))],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 280, height: 180)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                
                // 封印シール
                if tearProgress < 1 {
                    Circle()
                        .fill(Color.red.opacity(0.9))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text("🔒")
                                .font(.title2)
                        )
                        .scaleEffect(1 - tearProgress * 0.5)
                        .opacity(1 - tearProgress)
                }
                
                // 破れる進捗バー
                VStack(spacing: 8) {
                    Spacer()
                    
                    // 破線
                    ZStack(alignment: .leading) {
                        // 背景の破線
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundColor(.gray.opacity(0.5))
                            .frame(height: 2)
                        
                        // 破れた部分
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 240 * tearProgress, height: 4)
                    }
                    .frame(width: 240)
                    
                    Text(tearProgress < 0.3 ? "👆 指でスワイプして開封" : tearProgress < 1 ? "もう少し..." : "")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.7))
                    
                    Spacer().frame(height: 20)
                }
                .frame(height: 180)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = min(1, max(0, value.translation.width / 240))
                        
                        // 進捗に応じてハプティクス
                        if progress > tearProgress {
                            let progressDiff = progress - tearProgress
                            if progressDiff > 0.1 {
                                if progress < 0.5 {
                                    impactLight.impactOccurred()
                                } else if progress < 0.8 {
                                    impactMedium.impactOccurred()
                                } else {
                                    impactHeavy.impactOccurred()
                                }
                            }
                        }
                        
                        tearProgress = progress
                    }
                    .onEnded { value in
                        if tearProgress >= 0.95 {
                            openEnvelope()
                        } else {
                            withAnimation {
                                tearProgress = 0
                            }
                        }
                    }
            )
        }
    }
    
    // MARK: - 手紙ペーパー（封筒から出てくる）
    
    private var letterPaper: some View {
        VStack(spacing: 16) {
            // 手紙のヘッダー
            Text(letter.createdAt.jaFullDateString)
                .font(.caption)
                .foregroundColor(.gray)
            
            // 本文プレビュー
            Text(letter.content)
                .font(.body)
                .foregroundColor(.black)
                .lineSpacing(4)
                .lineLimit(8)
                .multilineTextAlignment(.leading)
        }
        .padding(24)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
    }
    
    // MARK: - 全文表示
    
    private var fullLetterContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ヘッダー
                VStack(spacing: 8) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    
                    Text("過去のあなたからの手紙")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(letter.createdAt.jaFullDateString)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                
                // 手紙風のカード
                VStack(alignment: .leading, spacing: 16) {
                    Text(letter.content)
                        .font(.body)
                        .foregroundColor(.black)
                        .lineSpacing(6)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                )
                
                Spacer(minLength: 60)
            }
            .padding()
        }
    }
    
    // MARK: - 開封アニメーション
    
    private func openEnvelope() {
        // 成功ハプティクス
        notificationFeedback.notificationOccurred(.success)
        
        // ステップ1: 手紙が封筒の後ろから出てくる
        withAnimation(.easeOut(duration: 0.4)) {
            letterPaperOpacity = 1
            letterPaperOffset = -100
        }
        
        // ステップ2: 封筒がフェードアウトして縮小
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.4)) {
                envelopeOpacity = 0
                envelopeScale = 0.8
            }
        }
        
        // ステップ3: 手紙が上に移動して消える → 全文表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                letterPaperOffset = -400
                letterPaperOpacity = 0
            }
        }
        
        // ステップ4: 全文表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showFullContent = true
            withAnimation(.easeIn(duration: 0.5)) {
                fullContentOpacity = 1
            }
        }
        
        // 開封処理を実行
        onOpen()
    }
}
