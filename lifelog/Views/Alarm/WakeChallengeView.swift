//
//  WakeChallengeView.swift
//  lifelog
//

import Combine
import CoreMotion
import SwiftUI

struct WakeChallengeView: View {
    enum Mode {
        case alarm
        case preview
    }

    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @FocusState private var isInputFocused: Bool

    let alarm: WakeAlarm
    let mode: Mode
    let onFinish: () -> Void

    @State private var answerText: String = ""
    @State private var feedbackMessage: String?
    @State private var successCount: Int = 0
    @State private var currentMathQuestion = MentalMathQuestion.make()
    @State private var memoryDigits: String = ""
    @State private var isShowingMemoryDigits = false
    @State private var targetString: String = ""
    @State private var isCompleting = false
    @State private var routinePromptPreset: MorningRoutinePreset?
    @State private var routineErrorMessage: String?
    @StateObject private var shakeDetector = ShakeDetector()

    private let mathTarget = 3
    private let memoryTarget = 3
    private let randomStringTarget = 2
    private let shakeTarget = 18

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.08, blue: 0.04), Color(red: 0.35, green: 0.15, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                header
                challengeCard
                footer
            }
            .padding(24)
        }
        .interactiveDismissDisabled(mode == .alarm)
        .onAppear {
            prepareChallenge()
        }
        .onDisappear {
            shakeDetector.stop()
        }
        .onChange(of: shakeDetector.shakeCount) { _, count in
            guard alarm.challengeMethod == .shake else { return }
            guard count >= shakeTarget else { return }
            completeChallenge()
        }
        .confirmationDialog(
            "朝ルーティンを開始しますか？",
            isPresented: Binding(
                get: { routinePromptPreset != nil },
                set: { if !$0 { routinePromptPreset = nil } }
            ),
            titleVisibility: .visible,
            presenting: routinePromptPreset
        ) { preset in
            Button("開始する") {
                startMorningRoutine(with: preset)
            }
            Button("今回はスキップ", role: .cancel) {
                routinePromptPreset = nil
                onFinish()
            }
        } message: { preset in
            Text("\(preset.title)\n\(preset.summaryText)")
        }
        .alert("朝ルーティン", isPresented: Binding(
            get: { routineErrorMessage != nil },
            set: { if !$0 { routineErrorMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(routineErrorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .alarm ? "解除テスト" : "解除テストを試す")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text(alarm.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

            Text("\(alarm.timeText) ・ \(alarm.challengeMethod.title)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var challengeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(progressLabel, systemImage: alarm.challengeMethod.iconName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if isCompleting {
                    ProgressView()
                        .tint(.white)
                }
            }

            switch alarm.challengeMethod {
            case .mentalMath:
                mentalMathBody
            case .shortTermMemory:
                shortTermMemoryBody
            case .randomString:
                randomStringBody
            case .shake:
                shakeBody
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(22)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .alarm ? "テストをクリアするとアラームを停止します。" : "プレビューでは停止処理は行いません。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))

            if mode == .preview {
                Button("閉じる") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
    }

    private var mentalMathBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(currentMathQuestion.prompt)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            TextField("答えを入力", text: $answerText)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.black)
                .focused($isInputFocused)

            Button("回答") {
                submitMentalMath()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var shortTermMemoryBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isShowingMemoryDigits ? "この数字を覚えてください" : "表示された数字をそのまま入力")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.82))

            Text(isShowingMemoryDigits ? memoryDigits : String(repeating: "•", count: max(memoryDigits.count, 4)))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .tracking(6)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if !isShowingMemoryDigits {
                TextField("数字を入力", text: $answerText)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.black)
                    .focused($isInputFocused)

                Button("回答") {
                    submitMemoryAnswer()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var randomStringBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("表示どおりに入力してください")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.82))

            Text(targetString)
                .font(.system(size: 34, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            TextField("文字列を入力", text: $answerText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.black)
                .focused($isInputFocused)

            Button("回答") {
                submitRandomString()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var shakeBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("端末をしっかり振ってください")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.82))

            ProgressView(value: min(Double(shakeDetector.shakeCount), Double(shakeTarget)), total: Double(shakeTarget))
                .tint(.white)

            Text("\(min(shakeDetector.shakeCount, shakeTarget)) / \(shakeTarget)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("大きな振りだけをカウントします。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
        }
    }

    private var progressLabel: String {
        switch alarm.challengeMethod {
        case .mentalMath:
            return "暗算 \(successCount) / \(mathTarget)"
        case .shortTermMemory:
            return "短期記憶 \(successCount) / \(memoryTarget)"
        case .randomString:
            return "文字列入力 \(successCount) / \(randomStringTarget)"
        case .shake:
            return "シェイク \(min(shakeDetector.shakeCount, shakeTarget)) / \(shakeTarget)"
        }
    }

    private func prepareChallenge() {
        feedbackMessage = nil
        answerText = ""

        switch alarm.challengeMethod {
        case .mentalMath:
            currentMathQuestion = MentalMathQuestion.make()
            focusInputSoon()

        case .shortTermMemory:
            startMemoryRound()

        case .randomString:
            targetString = Self.makeRandomString(length: 6)
            focusInputSoon()

        case .shake:
            shakeDetector.start()
        }
    }

    private func submitMentalMath() {
        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let answer = Int(trimmed) else {
            feedbackMessage = "数字で入力してください。"
            return
        }

        if answer == currentMathQuestion.answer {
            successCount += 1
            if successCount >= mathTarget {
                completeChallenge()
                return
            }
            feedbackMessage = "正解。次の問題です。"
            answerText = ""
            currentMathQuestion = MentalMathQuestion.make()
            focusInputSoon()
        } else {
            feedbackMessage = "違います。最初からやり直しです。"
            successCount = 0
            answerText = ""
            currentMathQuestion = MentalMathQuestion.make()
            focusInputSoon()
        }
    }

    private func startMemoryRound() {
        answerText = ""
        feedbackMessage = nil
        memoryDigits = Self.makeDigits(length: min(4 + successCount, 6))
        isShowingMemoryDigits = true

        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .seconds(2))
            isShowingMemoryDigits = false
            focusInputSoon()
        }
    }

    private func submitMemoryAnswer() {
        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == memoryDigits {
            successCount += 1
            if successCount >= memoryTarget {
                completeChallenge()
                return
            }
            feedbackMessage = "正解。次の桁数へ進みます。"
            startMemoryRound()
        } else {
            feedbackMessage = "違います。最初からやり直しです。"
            successCount = 0
            startMemoryRound()
        }
    }

    private func submitRandomString() {
        let normalizedAnswer = answerText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if normalizedAnswer == targetString {
            successCount += 1
            if successCount >= randomStringTarget {
                completeChallenge()
                return
            }
            feedbackMessage = "正解。もう1回です。"
            answerText = ""
            targetString = Self.makeRandomString(length: 6)
            focusInputSoon()
        } else {
            feedbackMessage = "違います。最初からやり直しです。"
            successCount = 0
            answerText = ""
            targetString = Self.makeRandomString(length: 6)
            focusInputSoon()
        }
    }

    private func completeChallenge() {
        guard !isCompleting else { return }
        isCompleting = true
        feedbackMessage = "クリアしました。"
        shakeDetector.stop()

        switch mode {
        case .alarm:
            _Concurrency.Task {
                await store.markWakeChallengeCompleted(for: alarm.id, shouldStopAlarm: true)
                await MainActor.run {
                    if let presetID = alarm.morningRoutinePresetID,
                       let preset = store.morningRoutinePreset(id: presetID) {
                        feedbackMessage = "アラームを停止しました。"
                        isCompleting = false
                        routinePromptPreset = preset
                    } else {
                        onFinish()
                    }
                }
            }

        case .preview:
            _Concurrency.Task { @MainActor in
                try? await _Concurrency.Task.sleep(for: .seconds(0.45))
                onFinish()
            }
        }
    }

    private func focusInputSoon() {
        guard alarm.challengeMethod != .shake else { return }
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .milliseconds(250))
            isInputFocused = true
        }
    }

    private static func makeDigits(length: Int) -> String {
        (0..<length)
            .map { _ in String(Int.random(in: 0...9)) }
            .joined()
    }

    private static func makeRandomString(length: Int) -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }

    private func startMorningRoutine(with preset: MorningRoutinePreset) {
        guard !isCompleting else { return }
        isCompleting = true

        _Concurrency.Task {
            do {
                _ = try await store.startMorningRoutine(presetID: preset.id, sourceAlarmID: alarm.id)
                await MainActor.run {
                    routinePromptPreset = nil
                    deepLinkManager.requestMorningRoutinePresentation()
                    onFinish()
                }
            } catch {
                await MainActor.run {
                    isCompleting = false
                    routineErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct MentalMathQuestion {
    let lhs: Int
    let rhs: Int
    let usesAddition: Bool

    var answer: Int {
        usesAddition ? lhs + rhs : lhs - rhs
    }

    var prompt: String {
        "\(lhs) \(usesAddition ? "+" : "-") \(rhs)"
    }

    static func make() -> MentalMathQuestion {
        let usesAddition = Bool.random()
        if usesAddition {
            return MentalMathQuestion(
                lhs: Int.random(in: 12...59),
                rhs: Int.random(in: 8...34),
                usesAddition: true
            )
        }

        let lhs = Int.random(in: 35...88)
        let rhs = Int.random(in: 7...min(29, lhs - 4))
        return MentalMathQuestion(lhs: lhs, rhs: rhs, usesAddition: false)
    }
}

@MainActor
private final class ShakeDetector: ObservableObject {
    @Published private(set) var shakeCount: Int = 0

    private let motionManager = CMMotionManager()
    private var lastCountedAt: TimeInterval = 0

    func start() {
        guard motionManager.isAccelerometerAvailable else { return }
        guard motionManager.isAccelerometerActive == false else { return }

        shakeCount = 0
        lastCountedAt = 0
        motionManager.accelerometerUpdateInterval = 0.08

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let magnitude = sqrt(
                (data.acceleration.x * data.acceleration.x) +
                (data.acceleration.y * data.acceleration.y) +
                (data.acceleration.z * data.acceleration.z)
            )

            let timestamp = Date().timeIntervalSinceReferenceDate
            guard magnitude > 2.3 else { return }
            guard (timestamp - self.lastCountedAt) > 0.33 else { return }

            self.lastCountedAt = timestamp
            self.shakeCount += 1
        }
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
    }
}
