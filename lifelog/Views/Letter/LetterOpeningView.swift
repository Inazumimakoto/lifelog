//
//  LetterOpeningView.swift
//  lifelog
//
//  Created by AI for Letter to the Future feature
//

import SwiftUI
import UIKit

// MARK: - パーティクル（光の粒子）

struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var opacity: Double
    var speed: Double
}

struct ParticleView: View {
    @State private var particles: [Particle] = []
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, .orange.opacity(0.5), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 4
                            )
                        )
                        .frame(width: 8 * particle.scale, height: 8 * particle.scale)
                        .position(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                        .blur(radius: 0.5)
                }
            }
            .onAppear {
                startParticles(in: geometry.size)
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    private func startParticles(in size: CGSize) {
        // 初期パーティクル生成
        for _ in 0..<15 {
            addParticle(in: size)
        }
        
        // 定期的にパーティクル追加
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            if particles.count < 20 {
                addParticle(in: size)
            }
            // 古いパーティクルを削除
            particles.removeAll { $0.opacity <= 0 }
        }
    }
    
    private func addParticle(in size: CGSize) {
        let particle = Particle(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: 0...size.height),
            scale: CGFloat.random(in: 0.5...1.5),
            opacity: Double.random(in: 0.3...0.8),
            speed: Double.random(in: 2...4)
        )
        particles.append(particle)
        
        // アニメーションで上に浮遊させてフェードアウト
        withAnimation(.easeOut(duration: particle.speed)) {
            if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                particles[index].y -= 100
                particles[index].opacity = 0
            }
        }
    }
}

// MARK: - メインビュー

struct LetterOpeningView: View {
    let letter: Letter
    var onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    // 登場アニメーション用
    @State private var backgroundOpacity: Double = 0
    @State private var envelopeOffset: CGFloat = -400
    @State private var envelopeRotation: Double = -5
    @State private var showEnvelope = false
    @State private var showText = false
    @State private var showParticles = false
    @State private var glowOpacity: Double = 0
    
    // 開封アニメーション用
    @State private var tearProgress: CGFloat = 0
    @State private var isOpened = false
    @State private var envelopeScale: CGFloat = 1
    @State private var envelopeOpacity: Double = 1
    @State private var letterPaperOffset: CGFloat = 0
    @State private var letterPaperOpacity: Double = 0
    @State private var showFullContent = false
    @State private var fullContentOpacity: Double = 0
    
    // ハプティクス
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    /// 手紙を書いてから経過した期間を文字列で返す
    private var timeSinceCreation: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: letter.createdAt, to: Date())
        
        if let years = components.year, years > 0 {
            if let months = components.month, months > 0 {
                return "\(years)年\(months)ヶ月前のあなたから"
            }
            return "\(years)年前のあなたから"
        } else if let months = components.month, months > 0 {
            return "\(months)ヶ月前のあなたから"
        } else if let days = components.day, days > 0 {
            return "\(days)日前のあなたから"
        } else {
            return "今日のあなたから"
        }
    }
    
    var body: some View {
        ZStack {
            // 背景（ディミング）
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
            
            Color(uiColor: UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1))
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
            
            // パーティクル効果
            if showParticles && !showFullContent {
                ParticleView()
                    .opacity(0.6)
            }
            
            // 封筒の周りのグロー効果
            if showEnvelope && !showFullContent {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.orange.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .opacity(glowOpacity)
                    .blur(radius: 30)
            }
            
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
                    .opacity(backgroundOpacity)
                }
                
                Spacer()
                
                if showFullContent {
                    // 開封後: 手紙の全文表示
                    fullLetterContent
                        .opacity(fullContentOpacity)
                } else if showEnvelope {
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
                            .offset(y: envelopeOffset)
                            .rotationEffect(.degrees(envelopeRotation))
                    }
                }
                
                Spacer()
            }
        }
        .onAppear {
            startEntranceAnimation()
        }
    }
    
    // MARK: - 登場アニメーション
    
    private func startEntranceAnimation() {
        // ハプティクス準備
        impactRigid.prepare()
        
        // ステップ1: 背景がふわっと暗くなる (0.3秒)
        withAnimation(.easeIn(duration: 0.3)) {
            backgroundOpacity = 1
        }
        
        // ステップ2: 封筒が上から降りてくる (0.5秒後、スプリング)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showEnvelope = true
            showParticles = true
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6, blendDuration: 0)) {
                envelopeOffset = 0
                envelopeRotation = 0
            }
            
            // ステップ3: 着地ハプティクス (0.6秒後)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                impactRigid.impactOccurred(intensity: 0.8)
            }
            
            // グロー効果をフェードイン
            withAnimation(.easeIn(duration: 0.8)) {
                glowOpacity = 1
            }
        }
        
        // ステップ4: テキストが遅延フェードイン (0.9秒後)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeIn(duration: 0.4)) {
                showText = true
            }
        }
    }
    
    // MARK: - 封筒ビュー
    
    private var envelopeView: some View {
        VStack(spacing: 20) {
            // テキスト（遅延フェードイン）
            VStack(spacing: 8) {
                Text("📨 過去のあなたから手紙が届きました")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(letter.createdAt.jaFullDateString)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .opacity(showText ? 1 : 0)
            
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
                    .shadow(color: .orange.opacity(0.3), radius: 20, y: 5)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                
                // 封筒の宛先・日付情報
                VStack(alignment: .leading, spacing: 6) {
                    // 宛先
                    Text("To: 未来の自分へ")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundColor(.brown.opacity(0.8))
                    
                    Spacer().frame(height: 4)
                    
                    // 差出日
                    HStack(spacing: 4) {
                        Text("差出日:")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text(letter.createdAt.jaShortDateString)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.brown.opacity(0.7))
                    }
                    
                    // 到着日
                    HStack(spacing: 4) {
                        Text("到着日:")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text(letter.deliveryDate.jaShortDateString)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.brown.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(width: 280, height: 180, alignment: .topLeading)
                .opacity(tearProgress < 0.5 ? 1.0 : 1.0 - Double(tearProgress - 0.5) * 2.0)
                
                // 封印シール
                if tearProgress < 1 {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color.red.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text("🔒")
                                .font(.title2)
                        )
                        .shadow(color: .red.opacity(0.5), radius: 5)
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
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 240 * tearProgress, height: 4)
                            .shadow(color: .orange.opacity(0.5), radius: 3)
                    }
                    .frame(width: 240)
                    
                    Text(tearProgress < 0.3 ? "👆 指でスワイプして開封" : tearProgress < 1 ? "もう少し..." : "")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.7))
                        .opacity(showText ? 1 : 0)
                    
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
                // ヘッダー（簡潔に）
                VStack(spacing: 4) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    
                    Text(timeSinceCreation)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                
                // 手紙風のカード
                VStack(alignment: .leading, spacing: 20) {
                    // 見出し
                    Text("Dear 未来の自分へ")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundColor(.brown)
                    
                    // 区切り線
                    Rectangle()
                        .fill(Color.brown.opacity(0.2))
                        .frame(height: 1)
                    
                    // 本文
                    Text(letter.content)
                        .font(.body)
                        .foregroundColor(.black)
                        .lineSpacing(6)
                    
                    Spacer().frame(height: 8)
                    
                    // 署名
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Rectangle()
                                .fill(Color.brown.opacity(0.2))
                                .frame(width: 100, height: 1)
                            Text("\(letter.createdAt.jaFullDateString)のあなたより")
                                .font(.system(size: 12, design: .serif))
                                .foregroundColor(.gray)
                        }
                    }
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
        
        // パーティクルを非表示
        showParticles = false
        
        // ステップ1: 手紙が封筒の後ろから出てくる
        withAnimation(.easeOut(duration: 0.4)) {
            letterPaperOpacity = 1
            letterPaperOffset = -100
            glowOpacity = 0
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

