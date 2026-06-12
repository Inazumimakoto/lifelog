//
//  EnvelopeOpeningView.swift
//  lifelog
//
//  封筒オープン演出の共通コンポーネント。
//  「未来への手紙」(LetterOpeningView) と「大切な人への手紙」(SharedLetterOpeningView)
//  で完全に同一だったアニメーション・ハプティクス・パーティクルをここに一本化する。
//
//  画面ごとに異なるのは「色」「ヘッダー文言」「封筒に印字する宛先/差出」「手紙の中身」だけなので、
//  それらはパラメータ / @ViewBuilder クロージャとして外から注入する。
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

// MARK: - 破れた紙片パーティクル

struct TearParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var opacity: Double
}

/// 背景を漂う光の粒子。アクセントカラーは画面ごとに注入する。
struct ParticleView: View {
    let accentColor: Color
    @State private var particles: [Particle] = []
    @State private var timer: Timer?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, accentColor.opacity(0.5), .clear],
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

// MARK: - 封筒オープン演出（共通コンポーネント）

/// 封筒が降りてきて、なぞって開封し、手紙カードが拡大するまでの一連の演出を担う共通ビュー。
///
/// 画面固有の違いは以下のパラメータ/クロージャで注入する:
/// - `accentColor`: パーティクル・グロー・封筒影・破れ目の光のアクセント色
/// - `headerTitle` / `headerSubtitle`: 封筒上部に表示するヘッダー文言
/// - `recipientLabel`: 封筒に印字する宛先（例: "To: 未来の自分へ"）
/// - `senderValue` / `arrivalValue`: 封筒の「差出」「到着」欄の値
/// - `previewContent`: 開封前に手紙カードへ表示するプレビュー（折りたたみ時）
/// - `expandedContent`: 開封後に拡大表示する手紙の中身
/// - `onOpenStart`: 開封ジェスチャ完了直後に呼ぶ（旧 LetterOpeningView の onOpen 相当）
/// - `onExpand`: カード拡大タイミング(開封1.5秒後)で呼ぶ（旧 SharedLetterOpeningView の復号開始相当）
struct EnvelopeOpeningView<Preview: View, Expanded: View>: View {
    let accentColor: Color
    let headerTitle: String
    let headerSubtitle: String
    let recipientLabel: String
    let senderValue: String
    let arrivalValue: String
    @ViewBuilder let previewContent: () -> Preview
    @ViewBuilder let expandedContent: () -> Expanded
    let onOpenStart: () -> Void
    let onExpand: () -> Void

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
    @State private var envelopeScale: CGFloat = 1
    @State private var envelopeOpacity: Double = 1
    @State private var letterPaperOffset: CGFloat = 40 // 初期位置は少し下（隠れるように）
    @State private var letterPaperOpacity: Double = 0 // 登場アニメーション後に表示
    @State private var showFullContent = false
    @State private var isLetterExpanded = false // 手紙が拡大されたかどうか

    // 封筒の揺れ効果用
    @State private var shakeOffset: CGFloat = 0
    @State private var tearParticles: [TearParticle] = []

    // ハプティクス
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationFeedback = UINotificationFeedbackGenerator()

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
                ParticleView(accentColor: accentColor)
                    .opacity(0.6)
            }

            // 封筒の周りのグロー効果
            if showEnvelope && !showFullContent {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(0.3), .clear],
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

                ZStack {
                    // 1. 封筒上部（一番奥）- 下にスライド
                    if showEnvelope && !isLetterExpanded {
                        envelopeTopLayer
                            .scaleEffect(envelopeScale)
                            .opacity(envelopeOpacity)
                            .offset(y: envelopeOffset)
                            .rotationEffect(.degrees(envelopeRotation))
                            .zIndex(0)
                    }

                    // 2. 手紙カード（小→大に拡張）
                    if showEnvelope || isLetterExpanded {
                        expandableLetterCard
                            .opacity(letterPaperOpacity)
                            .zIndex(1)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isLetterExpanded)
                    }

                    // 3. 封筒下部（一番手前）- 下にスライド
                    if showEnvelope && !isLetterExpanded {
                        envelopeBottomLayer
                            .scaleEffect(envelopeScale)
                            .opacity(envelopeOpacity)
                            .offset(y: envelopeOffset)
                            .rotationEffect(.degrees(envelopeRotation))
                            .zIndex(2)
                    }
                }

                Spacer()
            }
        }
        // fullScreenCoverで開いた時に確実にアニメーションを開始（.onAppearより.taskの方が確実）
        .task {
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

        // ステップ2: 封筒が上から降りてくる (0.3秒後、スプリング)
        // ※ 以下の asyncAfter ディレイは登場演出のシーケンス。各ディレイは上の
        //    withAnimation の duration と同期するよう意図的に決めているので変更しないこと。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showEnvelope = true
            showParticles = true

            withAnimation(.spring(response: 0.6, dampingFraction: 0.6, blendDuration: 0)) {
                envelopeOffset = 0
                envelopeRotation = 0
            }

            // ステップ3: 着地ハプティクス（封筒が着地するスプリングのピークに合わせて0.5秒後）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                impactRigid.impactOccurred(intensity: 0.8)
            }

            // グロー効果をフェードイン
            withAnimation(.easeIn(duration: 0.8)) {
                glowOpacity = 1
            }

            // ステップ3.5: 手紙をフェードイン（封筒着地後の0.5秒後）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 0.3)) {
                    letterPaperOpacity = 1
                }
            }
        }

        // ステップ4: テキストが遅延フェードイン（封筒着地後の0.9秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeIn(duration: 0.4)) {
                showText = true
            }
        }
    }

    // MARK: - 封筒上部レイヤー（一番奥）

    private var envelopeTopLayer: some View {
        VStack(spacing: 16) {
            // テキスト（遅延フェードイン）
            VStack(spacing: 8) {
                Text(headerTitle)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .opacity(showText ? 1 : 0)

            // 封筒上部 + ジッパー裏の背景
            ZStack {
                VStack(spacing: 0) {
                    ZStack {
                        // ベース
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.96, green: 0.91, blue: 0.84),
                                        Color(red: 0.92, green: 0.86, blue: 0.78)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // テクスチャ
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.15))

                        // 縁取り
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.brown.opacity(0.25), lineWidth: 1.5)
                    }
                    .frame(width: 260, height: 40)
                    .clipped()

                    // ジッパー裏の背景（ジッパー部分）
                    Rectangle()
                        .fill(Color(red: 0.40, green: 0.35, blue: 0.30))
                        .frame(width: 260, height: 24)

                    Spacer()
                }
                .frame(width: 260, height: 340)
            }
            .offset(x: shakeOffset)
        }
    }

    // MARK: - 封筒下部レイヤー（一番手前）

    private var envelopeBottomLayer: some View {
        VStack(spacing: 16) {
            // 上部テキスト用のスペーサー（位置を合わせるため）
            VStack(spacing: 8) {
                Text(headerTitle)
                    .font(.headline)
                    .foregroundColor(.clear) // 透明（位置合わせ用）

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.clear)
            }

            // 封筒下部 + ジッパー + ヒント + パーティクル
            ZStack {
                // 封筒の下部
                VStack(spacing: 0) {
                    Spacer().frame(height: 64) // 上部(40) + ジッパー(24)

                    ZStack {
                        // ベース
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.92, green: 0.86, blue: 0.78),
                                        Color(red: 0.88, green: 0.82, blue: 0.74)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // テクスチャ
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .brown.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        // 縁取り
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.brown.opacity(0.25), lineWidth: 1.5)

                        // 宛先・日付情報
                        VStack(alignment: .leading, spacing: 12) {
                            Spacer().frame(height: 6)

                            Text(recipientLabel)
                                .font(.system(size: 18, weight: .medium, design: .serif))
                                .foregroundColor(.brown.opacity(0.85))
                                .italic()

                            Spacer()

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text("差出")
                                        .font(.system(size: 10))
                                        .foregroundColor(.brown.opacity(0.5))
                                    Text(senderValue)
                                        .font(.system(size: 11, weight: .medium, design: .serif))
                                        .foregroundColor(.brown.opacity(0.7))
                                }
                                HStack(spacing: 8) {
                                    Text("到着")
                                        .font(.system(size: 10))
                                        .foregroundColor(.brown.opacity(0.5))
                                    Text(arrivalValue)
                                        .font(.system(size: 11, weight: .medium, design: .serif))
                                        .foregroundColor(.brown.opacity(0.7))
                                }
                            }

                            Spacer().frame(height: 24)
                        }
                        .padding(.horizontal, 28)
                    }
                    .frame(width: 260, height: 276)
                    .shadow(color: accentColor.opacity(0.15), radius: 30, y: 10)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                }
                .frame(width: 260, height: 340)

                // 開封ジッパー
                VStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        if tearProgress < 1.0 {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: 260 * tearProgress)

                                ZStack {
                                    Color(red: 0.93, green: 0.88, blue: 0.80)

                                    VStack {
                                        Rectangle()
                                            .fill(Color.brown.opacity(0.4))
                                            .frame(height: 1)
                                            .mask(Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                                        Spacer()
                                        Rectangle()
                                            .fill(Color.brown.opacity(0.4))
                                            .frame(height: 1)
                                            .mask(Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                                    }
                                    .padding(.vertical, 1)

                                    HStack(spacing: 4) {
                                        Text("OPEN")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.brown.opacity(0.5))
                                            .fixedSize()
                                            .lineLimit(1)
                                            .padding(.leading, 34)

                                        Image(systemName: "chevron.right.2")
                                            .font(.caption2)
                                            .foregroundColor(.brown.opacity(0.5))

                                        Spacer()

                                        Image(systemName: "chevron.right.2")
                                            .font(.caption2)
                                            .foregroundColor(.brown.opacity(0.3))
                                            .padding(.trailing, 12)
                                    }
                                }
                                .overlay(
                                    HStack {
                                        ZStack {
                                            UnevenRoundedRectangle(
                                                topLeadingRadius: 4,
                                                bottomLeadingRadius: 4,
                                                bottomTrailingRadius: 0,
                                                topTrailingRadius: 0
                                            )
                                            .fill(Color(red: 0.88, green: 0.82, blue: 0.74))
                                            .shadow(color: .black.opacity(0.1), radius: 1, x: -1, y: 0)

                                            HStack(spacing: 2) {
                                                ForEach(0..<3, id: \.self) { _ in
                                                    Rectangle()
                                                        .fill(Color.brown.opacity(0.3))
                                                        .frame(width: 1, height: 10)
                                                }
                                            }
                                        }
                                        .frame(width: 24)

                                        Spacer()
                                    }
                                )
                            }
                            .frame(height: 24)
                            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                        }

                        if tearProgress > 0 && tearProgress < 1.0 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, accentColor.opacity(0.5), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 40, height: 24)
                                .offset(x: 260 * tearProgress - 20)
                        }
                    }
                    .frame(width: 260, height: 24)
                    .clipped()
                    .padding(.top, 40)

                    Spacer()
                }
                .frame(width: 260, height: 340)

                // スワイプヒント
                VStack {
                    Spacer()
                    Text(tearProgress < 0.3 ? "👆 上をなぞって開封" : tearProgress < 1 ? "もう少し..." : "")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.brown.opacity(0.6))
                        .opacity(showText ? 1 : 0)
                }
                .frame(height: 340)
                .padding(.bottom, -40)

                // パーティクル
                ForEach(tearParticles) { particle in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(white: 0.95))
                        .frame(width: 5 * particle.scale, height: 8 * particle.scale)
                        .rotationEffect(.degrees(particle.rotation))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                        .offset(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                }
            }
            .offset(x: shakeOffset)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = min(1, max(0, value.translation.width / 220))

                        if progress > tearProgress {
                            let progressDiff = progress - tearProgress
                            let hapticThreshold = max(0.03, 0.08 - progress * 0.05)

                            if progressDiff > hapticThreshold {
                                let intensity = min(1.0, 0.3 + progress * 0.7)
                                if progress < 0.3 {
                                    impactLight.impactOccurred(intensity: intensity)
                                } else if progress < 0.6 {
                                    impactMedium.impactOccurred(intensity: intensity)
                                } else if progress < 0.85 {
                                    impactHeavy.impactOccurred(intensity: intensity)
                                } else {
                                    impactRigid.impactOccurred(intensity: 1.0)
                                }

                                addTearParticle(at: progress)
                            }
                        }

                        let shakeIntensity = progress * 2.5
                        withAnimation(.linear(duration: 0.05)) {
                            shakeOffset = CGFloat.random(in: -shakeIntensity...shakeIntensity)
                        }

                        tearProgress = progress
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                            shakeOffset = 0
                        }

                        if tearProgress >= 0.95 {
                            openEnvelope()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                tearProgress = 0
                            }
                            tearParticles.removeAll()
                        }
                    }
            )
        }
    }

    // MARK: - 拡張可能な手紙カード

    private var expandableLetterCard: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            // カードサイズの計算
            let cardWidth: CGFloat = isLetterExpanded ? screenWidth - 32 : 220
            let cardHeight: CGFloat = isLetterExpanded ? screenHeight - 100 : 180

            ScrollView(showsIndicators: isLetterExpanded) {
                VStack(alignment: .leading, spacing: isLetterExpanded ? 20 : 12) {
                    if isLetterExpanded {
                        expandedContent()
                    } else {
                        previewContent()
                    }
                }
                .padding(isLetterExpanded ? 24 : 16)
            }
            .scrollDisabled(!isLetterExpanded)
            .frame(width: cardWidth, height: isLetterExpanded ? cardHeight : 180) // プレビュー時は固定高さ
            .clipped() // はみ出し防止
            .background(
                RoundedRectangle(cornerRadius: isLetterExpanded ? 16 : 6)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(isLetterExpanded ? 0.3 : 0.2), radius: isLetterExpanded ? 20 : 8, y: isLetterExpanded ? 10 : 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: isLetterExpanded ? 16 : 6)) // 角丸クリップ
            .position(
                x: geometry.size.width / 2,
                y: isLetterExpanded ? geometry.size.height / 2 : geometry.size.height / 2 + letterPaperOffset
            )
        }
    }

    // MARK: - パーティクル追加（破れ目から紙片が散る）

    private func addTearParticle(at progress: CGFloat) {
        // 破れ目の位置（封筒の中心(0,0)からの相対座標）
        // 封筒サイズ: 260x340
        // ジッパー帯の位置: 上から40px + 帯の高さ24px = 上から64px
        // 封筒の中心からのy座標: -170 + 64 = -106 (下端) -> -115 (少し上)
        let tearX = -130 + (260 * progress) // 左端(-130)から右端(+130)へ
        let tearY: CGFloat = -115 // ジッパー帯の中央付近

        // 1〜2個のパーティクルを追加
        let particleCount = Int.random(in: 1...2)
        for _ in 0..<particleCount {
            let particle = TearParticle(
                x: tearX + CGFloat.random(in: -10...10),
                y: tearY + CGFloat.random(in: -5...5),
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.8...1.5),
                opacity: 1.0
            )
            tearParticles.append(particle)

            // パーティクルを落下させながらフェードアウト
            withAnimation(.easeOut(duration: Double.random(in: 0.5...1.0))) {
                if let index = tearParticles.firstIndex(where: { $0.id == particle.id }) {
                    tearParticles[index].y += CGFloat.random(in: 40...80)
                    tearParticles[index].x += CGFloat.random(in: -15...15)
                    tearParticles[index].rotation += Double.random(in: 90...180)
                    tearParticles[index].opacity = 0
                }
            }
        }

        // 古いパーティクルを削除
        tearParticles.removeAll { $0.opacity <= 0 }
    }

    // MARK: - 開封アニメーション
    //
    // ⚠️ 以下の asyncAfter ディレイ(0.1/0.25/0.35/0.45/0.8/1.5/2.5)はすべて開封演出のシーケンス。
    //    手紙が頭を出す→封筒が下へ消える→カードが拡大する各 withAnimation の duration と
    //    同期するよう意図的にチューニングしている。ハプティクスの連打も「達成感」を出す演出なので、
    //    数値は変更しないこと。

    private func openEnvelope() {
        // 開封ジェスチャ完了直後に呼ぶ画面固有処理（旧 LetterOpeningView の onOpen 相当）
        onOpenStart()

        // 💥 最大級ハプティクス - 開封の達成感を演出

        // フェーズ1: 強い衝撃で始まる
        impactRigid.impactOccurred(intensity: 1.0)

        // フェーズ2: 成功通知
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            notificationFeedback.notificationOccurred(.success)
        }

        // フェーズ3: 連続した強い振動パターン（お祝い感）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            impactHeavy.impactOccurred(intensity: 1.0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            impactHeavy.impactOccurred(intensity: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            impactRigid.impactOccurred(intensity: 1.0)
        }

        // フェーズ4: 最後のフィニッシュ（手紙が拡大するタイミング = 1.5秒後に合わせる）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            impactHeavy.impactOccurred(intensity: 0.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                notificationFeedback.notificationOccurred(.success)
            }
        }

        // パーティクルを非表示
        showParticles = false

        // ステップ1: 手紙が封筒から少し頭を出す (spring 0.6秒)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            letterPaperOpacity = 1
            letterPaperOffset = -120 // 少し頭を出す
            glowOpacity = 0
        }

        // ステップ2: 封筒が下にスライドして消える（頭出しアニメーション完了後の0.8秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.6)) {
                envelopeOffset = 1000 // 画面下にスライド
            }
        }

        // ステップ3: 封筒が消えてから手紙カードが拡大（1.5秒後 = 封筒退場完了に合わせる）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isLetterExpanded = true // カードが拡大
                letterPaperOffset = 0 // 中央に戻る
            }

            // 拡大タイミングで呼ぶ画面固有処理（旧 SharedLetterOpeningView の復号開始相当）
            onExpand()
        }

        // ステップ4: クリーンアップ（カード拡大の後、2.5秒後に封筒ビューを破棄）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showEnvelope = false
        }
    }
}
