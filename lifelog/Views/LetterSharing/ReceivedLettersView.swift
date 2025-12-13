//
//  ReceivedLettersView.swift
//  lifelog
//
//  大切な人への手紙 - 受信した手紙一覧
//

import SwiftUI
import UIKit

/// 受信した手紙一覧画面
struct ReceivedLettersView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var letters: [LetterReceivingService.ReceivedLetter] = []  // Firestoreからの未開封のみ
    @State private var isLoading = true
    @State private var selectedLetter: LetterReceivingService.ReceivedLetter?  // 未開封用
    @State private var showingLetterDetail = false  // 開封アニメーション用
    @State private var selectedOpenedLetter: SharedLetter?  // 開封済み用（ローカルデータ）
    @State private var showingOpenedLetterDetail = false  // 開封済み詳細用
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if letters.isEmpty {
                emptyStateView
            } else {
                letterListView
            }
        }
        .navigationTitle("受信した手紙")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadLetters()
        }
        .refreshable {
            await loadLetters()
        }
        // 未開封の手紙 → 開封アニメーション
        .fullScreenCover(isPresented: $showingLetterDetail, onDismiss: {
            selectedLetter = nil
            // 開封後にリストを更新
            _Concurrency.Task {
                await loadLetters()
            }
        }) {
            Group {
                if let letter = selectedLetter {
                    SharedLetterOpeningView(letter: letter)
                } else {
                    // フォールバック（通常は表示されない）
                    Color(uiColor: UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1))
                        .ignoresSafeArea()
                }
            }
        }
        // 開封済みの手紙 → 通常表示
        .sheet(isPresented: $showingOpenedLetterDetail) {
            if let letter = selectedOpenedLetter {
                NavigationStack {
                    SharedLetterContentView(letter: letter)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.open")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("手紙はまだ届いていません")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("大切な人からの手紙を待ちましょう")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var letterListView: some View {
        let unreadLetters = letters.filter { $0.status == "delivered" }
        
        List {
            // 開封待ちセクション
            Section {
                if unreadLetters.isEmpty {
                    HStack {
                        Spacer()
                        Text("開封待ちの手紙はありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(unreadLetters) { letter in
                        Button(action: {
                            selectedLetter = letter
                        }) {
                            unreadLetterRow(letter)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Label("開封待ち", systemImage: "envelope.badge")
                    .font(.headline)
            }
            
            // 開封済みセクション
            Section {
                if store.sharedLetters.isEmpty {
                    HStack {
                        Spacer()
                        Text("開封済みの手紙はありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(store.sharedLetters) { letter in
                        Button(action: {
                            selectedOpenedLetter = letter  // 開封済み用（ローカル）
                        }) {
                            localLetterRow(letter)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())  // タップ領域を広げる
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteOpenedLetter(letter)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteOpenedLetter(letter)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Label("開封済み", systemImage: "envelope.open")
                    .font(.headline)
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: selectedLetter) { _, newLetter in
            if newLetter != nil {
                showingLetterDetail = true
            }
        }
        .onChange(of: selectedOpenedLetter) { _, newLetter in
            if newLetter != nil {
                showingOpenedLetterDetail = true
            }
        }
    }
    
    private func unreadLetterRow(_ letter: LetterReceivingService.ReceivedLetter) -> some View {
        HStack(spacing: 12) {
            // オレンジ封筒アイコン
            Image(systemName: "envelope.fill")
                .font(.title)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(letter.senderEmoji) \(letter.senderName)さんから")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text("\(formatDate(letter.deliveredAt))に届きました")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("開封")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .padding(.vertical, 8)
    }
    
    private func localLetterRow(_ letter: SharedLetter) -> some View {
        HStack(spacing: 12) {
            Text(letter.senderEmoji)
                .font(.title)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.senderName)
                    .font(.headline)
                
                Text("開封日: \(formatDate(letter.openedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func loadLetters() async {
        isLoading = true
        do {
            letters = try await LetterReceivingService.shared.getReceivedLetters()
        } catch {
            print("手紙取得エラー: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日 H:mm"
        return formatter.string(from: date)
    }
    
    private func deleteOpenedLetter(_ letter: SharedLetter) {
        withAnimation {
            store.deleteSharedLetter(letter.id)
        }
    }
}

// MARK: - 共有手紙開封用パーティクル（既存のParticle/TearParticleは別ファイルにあるため再利用）

fileprivate struct SharedParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var opacity: Double
    var speed: Double
}

fileprivate struct SharedTearParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var opacity: Double
}

fileprivate struct SharedParticleView: View {
    @State private var particles: [SharedParticle] = []
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, .blue.opacity(0.5), .clear],
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
        for _ in 0..<15 {
            addParticle(in: size)
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            if particles.count < 20 {
                addParticle(in: size)
            }
            particles.removeAll { $0.opacity <= 0 }
        }
    }
    
    private func addParticle(in size: CGSize) {
        let particle = SharedParticle(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: 0...size.height),
            scale: CGFloat.random(in: 0.5...1.5),
            opacity: Double.random(in: 0.3...0.8),
            speed: Double.random(in: 2...4)
        )
        particles.append(particle)
        
        withAnimation(.easeOut(duration: particle.speed)) {
            if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                particles[index].y -= 100
                particles[index].opacity = 0
            }
        }
    }
}

// MARK: - 共有手紙開封画面（既存のLetterOpeningViewと同じアニメーション）

struct SharedLetterOpeningView: View {
    let letter: LetterReceivingService.ReceivedLetter
    @EnvironmentObject private var store: AppDataStore
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
    @State private var letterPaperOffset: CGFloat = 40
    @State private var letterPaperOpacity: Double = 0
    @State private var letterScale: CGFloat = 1
    @State private var showFullContent = false
    @State private var fullContentOpacity: Double = 0
    @State private var isLetterExpanded = false
    @Namespace private var animation
    
    // 封筒の揺れ効果用
    @State private var shakeOffset: CGFloat = 0
    @State private var tearParticles: [SharedTearParticle] = []
    
    // 復号用
    @State private var isDecrypting = false
    @State private var decryptedLetter: LetterReceivingService.DecryptedLetter?
    @State private var errorMessage: String?
    
    // 写真用
    @State private var selectedPhotoIndex: Int = 0
    @State private var showFullscreenPhoto = false
    
    // ハプティクス
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        ZStack {
            // 背景
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
            
            Color(uiColor: UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1))
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
            
            // パーティクル効果
            if showParticles && !showFullContent {
                SharedParticleView()
                    .opacity(0.6)
            }
            
            // 封筒の周りのグロー効果
            if showEnvelope && !showFullContent {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue.opacity(0.3), .clear],
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
                    // 1. 封筒上部（一番奥）
                    if showEnvelope && !isLetterExpanded {
                        envelopeTopLayer
                            .scaleEffect(envelopeScale)
                            .opacity(envelopeOpacity)
                            .offset(y: envelopeOffset)
                            .rotationEffect(.degrees(envelopeRotation))
                            .zIndex(0)
                    }
                    
                    // 2. 手紙カード
                    if showEnvelope || isLetterExpanded {
                        expandableLetterCard
                            .opacity(letterPaperOpacity)
                            .zIndex(1)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isLetterExpanded)
                    }
                    
                    // 3. 封筒下部（一番手前）
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
        .task {
            // fullScreenCoverで開いた時に確実にアニメーションを開始
            startEntranceAnimation()
        }
        .fullScreenCover(isPresented: $showFullscreenPhoto) {
            fullscreenPhotoViewer
        }
    }
    
    // MARK: - 登場アニメーション
    
    private func startEntranceAnimation() {
        impactRigid.prepare()
        
        withAnimation(.easeIn(duration: 0.3)) {
            backgroundOpacity = 1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showEnvelope = true
            showParticles = true
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6, blendDuration: 0)) {
                envelopeOffset = 0
                envelopeRotation = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                impactRigid.impactOccurred(intensity: 0.8)
            }
            
            withAnimation(.easeIn(duration: 0.8)) {
                glowOpacity = 1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 0.3)) {
                    letterPaperOpacity = 1
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeIn(duration: 0.4)) {
                showText = true
            }
        }
    }
    
    // MARK: - 封筒上部レイヤー
    
    private var envelopeTopLayer: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("\(letter.senderEmoji) \(letter.senderName)さんから手紙が届きました")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(letter.deliveredAt.jaFullDateString)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .opacity(showText ? 1 : 0)
            
            ZStack {
                VStack(spacing: 0) {
                    ZStack {
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
                        
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.15))
                        
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.brown.opacity(0.25), lineWidth: 1.5)
                    }
                    .frame(width: 260, height: 40)
                    .clipped()
                    
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
    
    // MARK: - 封筒下部レイヤー
    
    private var envelopeBottomLayer: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("\(letter.senderEmoji) \(letter.senderName)さんから手紙が届きました")
                    .font(.headline)
                    .foregroundColor(.clear)
                
                Text(letter.deliveredAt.jaFullDateString)
                    .font(.subheadline)
                    .foregroundColor(.clear)
            }
            
            ZStack {
                VStack(spacing: 0) {
                    Spacer().frame(height: 64)
                    
                    ZStack {
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
                        
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .brown.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.brown.opacity(0.25), lineWidth: 1.5)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Spacer().frame(height: 6)
                            
                            Text("To: あなたへ")
                                .font(.system(size: 18, weight: .medium, design: .serif))
                                .foregroundColor(.brown.opacity(0.85))
                                .italic()
                            
                            Spacer()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text("差出")
                                        .font(.system(size: 10))
                                        .foregroundColor(.brown.opacity(0.5))
                                    Text(letter.senderName)
                                        .font(.system(size: 11, weight: .medium, design: .serif))
                                        .foregroundColor(.brown.opacity(0.7))
                                }
                                HStack(spacing: 8) {
                                    Text("到着")
                                        .font(.system(size: 10))
                                        .foregroundColor(.brown.opacity(0.5))
                                    Text(letter.deliveredAt.jaShortDateString)
                                        .font(.system(size: 11, weight: .medium, design: .serif))
                                        .foregroundColor(.brown.opacity(0.7))
                                }
                            }
                            
                            Spacer().frame(height: 24)
                        }
                        .padding(.horizontal, 28)
                    }
                    .frame(width: 260, height: 276)
                    .shadow(color: .blue.opacity(0.15), radius: 30, y: 10)
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
                                        colors: [.clear, .blue.opacity(0.5), .clear],
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
                    .onEnded { value in
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
            
            let cardWidth: CGFloat = isLetterExpanded ? screenWidth - 32 : 220
            let cardHeight: CGFloat = isLetterExpanded ? screenHeight - 100 : 180
            
            ScrollView(showsIndicators: isLetterExpanded) {
                VStack(alignment: .leading, spacing: isLetterExpanded ? 20 : 12) {
                    if isLetterExpanded {
                        if isDecrypting {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("復号中...")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else if let decrypted = decryptedLetter {
                            // ヘッダー
                            VStack(spacing: 4) {
                                Text(decrypted.senderEmoji)
                                    .font(.system(size: 40))
                                
                                Text("\(decrypted.senderName)さんより")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            
                            Text("Dear あなたへ")
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                                .foregroundColor(.brown)
                            
                            Rectangle()
                                .fill(Color.brown.opacity(0.2))
                                .frame(height: 1)
                            
                            // 本文
                            Text(decrypted.content)
                                .font(.body)
                                .foregroundColor(.black)
                                .lineSpacing(6)
                            
                            // 写真
                            if !decrypted.photos.isEmpty {
                                VStack(spacing: 12) {
                                    HStack {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .foregroundColor(.brown.opacity(0.6))
                                        Text("添付写真")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.brown.opacity(0.8))
                                        Spacer()
                                        Text("\(decrypted.photos.count)枚")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    TabView(selection: $selectedPhotoIndex) {
                                        ForEach(Array(decrypted.photos.enumerated()), id: \.offset) { index, photo in
                                            Image(uiImage: photo)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 200)
                                                .clipped()
                                                .tag(index)
                                                .onTapGesture {
                                                    showFullscreenPhoto = true
                                                }
                                        }
                                    }
                                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.top, 8)
                            }
                            
                            Spacer().frame(height: 16)
                            
                            HStack {
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Rectangle()
                                        .fill(Color.brown.opacity(0.2))
                                        .frame(width: 100, height: 1)
                                    Text("\(decrypted.deliveredAt.jaFullDateString)に届いた手紙")
                                        .font(.system(size: 12, design: .serif))
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer().frame(height: 60)
                        } else if let error = errorMessage {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                    } else {
                        // プレビュー
                        Text(letter.deliveredAt.jaFullDateString)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("\(letter.senderEmoji) \(letter.senderName)さんからの手紙")
                            .font(.subheadline)
                            .foregroundColor(.black)
                            .lineLimit(6)
                    }
                }
                .padding(isLetterExpanded ? 24 : 16)
            }
            .scrollDisabled(!isLetterExpanded)
            .frame(width: cardWidth, height: isLetterExpanded ? cardHeight : 180)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: isLetterExpanded ? 16 : 6)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(isLetterExpanded ? 0.3 : 0.2), radius: isLetterExpanded ? 20 : 8, y: isLetterExpanded ? 10 : 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: isLetterExpanded ? 16 : 6))
            .position(
                x: geometry.size.width / 2,
                y: isLetterExpanded ? geometry.size.height / 2 : geometry.size.height / 2 + letterPaperOffset
            )
        }
    }
    
    // MARK: - フルスクリーン写真ビューア
    
    private var fullscreenPhotoViewer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let decrypted = decryptedLetter {
                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(decrypted.photos.enumerated()), id: \.offset) { index, photo in
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullscreenPhoto = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
                
                if let decrypted = decryptedLetter {
                    Text("\(selectedPhotoIndex + 1) / \(decrypted.photos.count)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - パーティクル追加
    
    private func addTearParticle(at progress: CGFloat) {
        let tearX = -130 + (260 * progress)
        let tearY: CGFloat = -115
        
        let particleCount = Int.random(in: 1...2)
        for _ in 0..<particleCount {
            let particle = SharedTearParticle(
                x: tearX + CGFloat.random(in: -10...10),
                y: tearY + CGFloat.random(in: -5...5),
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.8...1.5),
                opacity: 1.0
            )
            tearParticles.append(particle)
            
            withAnimation(.easeOut(duration: Double.random(in: 0.5...1.0))) {
                if let index = tearParticles.firstIndex(where: { $0.id == particle.id }) {
                    tearParticles[index].y += CGFloat.random(in: 40...80)
                    tearParticles[index].x += CGFloat.random(in: -15...15)
                    tearParticles[index].rotation += Double.random(in: 90...180)
                    tearParticles[index].opacity = 0
                }
            }
        }
        
        tearParticles.removeAll { $0.opacity <= 0 }
    }
    
    // MARK: - 開封アニメーション
    
    private func openEnvelope() {
        impactRigid.impactOccurred(intensity: 1.0)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.notificationFeedback.notificationOccurred(.success)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.impactHeavy.impactOccurred(intensity: 1.0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.impactHeavy.impactOccurred(intensity: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.impactRigid.impactOccurred(intensity: 1.0)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.impactHeavy.impactOccurred(intensity: 0.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.notificationFeedback.notificationOccurred(.success)
            }
        }
        
        showParticles = false
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            letterPaperOpacity = 1
            letterPaperOffset = -120
            glowOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.6)) {
                envelopeOffset = 1000
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isLetterExpanded = true
                letterPaperOffset = 0
            }
            
            // 復号開始
            decryptLetter()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showEnvelope = false
        }
    }
    
    private func decryptLetter() {
        isDecrypting = true
        
        _Concurrency.Task {
            do {
                let decrypted = try await LetterReceivingService.shared.openLetter(letterId: letter.id)
                
                // ローカルに保存
                let photoPaths = await savePhotosLocally(decrypted.photos, letterId: letter.id)
                let sharedLetter = SharedLetter(
                    id: letter.id,
                    senderId: decrypted.senderId,
                    senderEmoji: decrypted.senderEmoji,
                    senderName: decrypted.senderName,
                    content: decrypted.content,
                    photoPaths: photoPaths,
                    deliveredAt: decrypted.deliveredAt,
                    openedAt: decrypted.openedAt ?? Date()
                )
                
                await MainActor.run {
                    store.addSharedLetter(sharedLetter)
                    decryptedLetter = decrypted
                    isDecrypting = false
                    HapticManager.success()
                }
                
                // Firestoreから削除
                try await LetterReceivingService.shared.deleteLetter(letterId: letter.id)
                print("✅ Firestoreから手紙を削除: \(letter.id)")
                
            } catch {
                await MainActor.run {
                    isDecrypting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func savePhotosLocally(_ photos: [UIImage], letterId: String) async -> [String] {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        
        let letterDir = documentsDir.appendingPathComponent("SharedLetterPhotos/\(letterId)")
        try? FileManager.default.createDirectory(at: letterDir, withIntermediateDirectories: true)
        
        var paths: [String] = []
        for (index, photo) in photos.enumerated() {
            let filename = "photo_\(index).jpg"
            let fileURL = letterDir.appendingPathComponent(filename)
            if let data = photo.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL)
                // 相対パスを保存
                paths.append("SharedLetterPhotos/\(letterId)/\(filename)")
            }
        }
        
        return paths
    }
}

// MARK: - 開封済み手紙の表示画面（ローカルデータ）

struct SharedLetterContentView: View {
    let letter: SharedLetter  // ローカル保存された手紙
    @Environment(\.dismiss) private var dismiss
    
    @State private var loadedImages: [UIImage] = []
    @State private var selectedPhotoIndex: Int = 0
    @State private var showFullscreenPhoto = false
    
    // 通報・ブロック用
    @State private var showReportSheet = false
    @State private var showBlockConfirmation = false
    @State private var showBlockSuccessAfterReport = false
    @State private var isBlocking = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ヘッダー
                VStack(spacing: 8) {
                    Text(letter.senderEmoji)
                        .font(.system(size: 50))
                    
                    Text("\(letter.senderName)さんからの手紙")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text(letter.openedAt.jaFullDateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                
                Divider()
                
                // 本文
                Text(letter.content)
                    .font(.body)
                    .lineSpacing(6)
                
                // 写真カルーセル（写真がある場合のみ）
                if !loadedImages.isEmpty {
                    Divider()
                    
                    VStack(spacing: 12) {
                        // セクションヘッダー
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .foregroundColor(.blue)
                            Text("添付写真")
                                .font(.headline)
                            Spacer()
                            Text("\(loadedImages.count)枚")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        // カルーセル
                        TabView(selection: $selectedPhotoIndex) {
                            ForEach(loadedImages.indices, id: \.self) { index in
                                Image(uiImage: loadedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .tag(index)
                                    .onTapGesture {
                                        showFullscreenPhoto = true
                                    }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                        .frame(height: 220)
                    }
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("手紙を読む")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showReportSheet = true
                    } label: {
                        Label("通報", systemImage: "exclamationmark.triangle")
                    }
                    
                    Button(role: .destructive) {
                        showBlockConfirmation = true
                    } label: {
                        Label("ブロック", systemImage: "hand.raised.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            loadPhotos()
        }
        .fullScreenCover(isPresented: $showFullscreenPhoto) {
            fullscreenPhotoViewer
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheetView(
                userName: letter.senderName,
                userId: letter.senderId,
                letterId: letter.id,
                onReportComplete: {
                    showBlockSuccessAfterReport = true
                }
            )
        }
        .alert("ブロックしますか？", isPresented: $showBlockConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("ブロック", role: .destructive) {
                blockUser()
            }
        } message: {
            Text("\(letter.senderName)さんからの手紙は今後届かなくなります。")
        }
        .alert("ブロックしますか？", isPresented: $showBlockSuccessAfterReport) {
            Button("いいえ", role: .cancel) { }
            Button("ブロックする", role: .destructive) {
                blockUser()
            }
        } message: {
            Text("通報を送信しました。このユーザーをブロックしますか？")
        }
    }
    
    private func blockUser() {
        isBlocking = true
        _Concurrency.Task {
            do {
                try await AuthService.shared.blockUser(letter.senderId)
                await MainActor.run {
                    isBlocking = false
                    HapticManager.success()
                }
            } catch {
                await MainActor.run {
                    isBlocking = false
                }
            }
        }
    }
    
    private func loadPhotos() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        for path in letter.photoPaths {
            let fullPath = documentsDir.appendingPathComponent(path)
            if let data = FileManager.default.contents(atPath: fullPath.path),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }
    }
    
    // MARK: - フルスクリーン写真ビューア
    
    private var fullscreenPhotoViewer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $selectedPhotoIndex) {
                ForEach(loadedImages.indices, id: \.self) { index in
                    Image(uiImage: loadedImages[index])
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            
            // 閉じるボタン
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullscreenPhoto = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
                
                // ページ表示
                if !loadedImages.isEmpty {
                    Text("\(selectedPhotoIndex + 1) / \(loadedImages.count)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - 通報シート

struct ReportSheetView: View {
    let userName: String
    let userId: String
    let letterId: String?
    let onReportComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ReportService.ReportReason?
    @State private var details: String = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(userName)さんを通報")
                        .font(.headline)
                } header: {
                    Text("通報対象")
                }
                
                Section {
                    ForEach(ReportService.ReportReason.allCases, id: \.self) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("通報理由")
                }
                
                Section {
                    TextField("詳細（任意）", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("詳細")
                }
            }
            .navigationTitle("通報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信") {
                        submitReport()
                    }
                    .disabled(selectedReason == nil || isSubmitting)
                }
            }
            .alert("通報を送信しました", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                    onReportComplete()
                }
            }
        }
    }
    
    private func submitReport() {
        guard let reason = selectedReason else { return }
        
        isSubmitting = true
        _Concurrency.Task {
            do {
                try await ReportService.shared.reportUser(
                    userId: userId,
                    reason: reason,
                    letterId: letterId,
                    details: details.isEmpty ? nil : details
                )
                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReceivedLettersView()
    }
}
