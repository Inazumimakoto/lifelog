import SwiftUI

/// Requirements §4.11: introduce one decision at a time, then guide shortcut and automation setup.
struct WallpaperCalendarShortcutInstallGuide<
    BackgroundContent: View,
    LayoutContent: View,
    PrivacyContent: View,
    PreviewContent: View,
    ManualGuide: View
>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage: Page = .welcome

    private let isWallpaperLoading: Bool
    private let onInstall: () -> Void
    private let onOpenShortcuts: () -> Void
    private let backgroundContent: () -> BackgroundContent
    private let layoutContent: () -> LayoutContent
    private let privacyContent: () -> PrivacyContent
    private let previewContent: () -> PreviewContent
    private let manualGuide: () -> ManualGuide

    private let automationSteps: [AutomationStep] = [
        AutomationStep(
            assetName: "WallpaperAutomationGuide01",
            instructions: [
                "ショートカットアプリの「オートメーション」を開きます。",
                "「新規オートメーション」をタップします。すでにある場合は、右上の「＋」をタップします。"
            ]
        ),
        AutomationStep(
            assetName: "WallpaperAutomationGuide02",
            instructions: ["一覧から「アプリ」を選びます。"]
        ),
        AutomationStep(
            assetName: "WallpaperAutomationGuide03",
            instructions: [
                "「選択」をタップしてlifelifyを選びます。",
                "「開いている」をオフにして、「閉じている」だけをオンにします。",
                "「すぐに実行」を選び、「実行時に通知」をオフにします。",
                "右上の「次へ」をタップします。"
            ]
        ),
        AutomationStep(
            assetName: "WallpaperAutomationGuide04",
            instructions: ["追加した「lifelify 壁紙カレンダー」を選びます。"]
        ),
        AutomationStep(
            assetName: "WallpaperAutomationGuide05",
            instructions: [
                "一覧に「lifelifyが閉じられたとき」と「lifelify 壁紙カレンダー」が表示されていることを確認します。",
                "確認できたらlifelifyに戻り、下の「設定を確認しました」をタップします。"
            ]
        )
    ]

    init(
        isWallpaperLoading: Bool = false,
        onInstall: @escaping () -> Void,
        onOpenShortcuts: @escaping () -> Void,
        @ViewBuilder backgroundContent: @escaping () -> BackgroundContent,
        @ViewBuilder layoutContent: @escaping () -> LayoutContent,
        @ViewBuilder privacyContent: @escaping () -> PrivacyContent,
        @ViewBuilder previewContent: @escaping () -> PreviewContent,
        @ViewBuilder manualGuide: @escaping () -> ManualGuide
    ) {
        self.isWallpaperLoading = isWallpaperLoading
        self.onInstall = onInstall
        self.onOpenShortcuts = onOpenShortcuts
        self.backgroundContent = backgroundContent
        self.layoutContent = layoutContent
        self.privacyContent = privacyContent
        self.previewContent = previewContent
        self.manualGuide = manualGuide
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    pageContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .id("wallpaperShortcut.top")
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                        .background(.background)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    navigationControls
                }
                .onChange(of: currentPage) { _, _ in
                    if reduceMotion {
                        proxy.scrollTo("wallpaperShortcut.top", anchor: .top)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("wallpaperShortcut.top", anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle("ロック画面カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if currentPage == .welcome {
                Text("ようこそ")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let stage = currentPage.stage {
                HStack(spacing: 8) {
                    Text(verbatim: "\(stage)/3")
                        .monospacedDigit()
                        .accessibilityIdentifier("wallpaperShortcut.progress")
                    Text(currentPage.stageTitle)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { index in
                        Capsule()
                            .fill(index <= stage ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
            }

            Text(currentPage.title)
                .font(currentPage == .welcome ? .largeTitle.bold() : .title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("wallpaperShortcut.pageTitle")
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .welcome:
            welcomeContent
        case .background:
            VStack(alignment: .leading, spacing: 24) {
                Text("好きな写真や色を選んでください。")
                    .fixedSize(horizontal: false, vertical: true)
                backgroundContent()
            }
        case .layout:
            VStack(alignment: .leading, spacing: 24) {
                Text("カレンダーに表示する週数を選んでください。")
                    .fixedSize(horizontal: false, vertical: true)
                layoutContent()
            }
        case .privacy:
            VStack(alignment: .leading, spacing: 24) {
                Text("ロック画面に表示する予定の情報を選びます。")
                    .fixedSize(horizontal: false, vertical: true)
                privacyContent()
            }
        case .preview:
            VStack(alignment: .leading, spacing: 20) {
                previewContent()
                Text("背景やレイアウトは、あとから変更できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .shortcutIntro:
            explanationContent(
                symbol: "square.stack.3d.up",
                text: "lifelifyがカレンダー画像を作り、Appleの「ショートカット」がiPhoneの壁紙に設定します。"
            )
        case .shortcutInstall:
            installationContent
        case .shortcutVerify:
            verificationContent
        case .automationIntro:
            explanationContent(
                symbol: "arrow.triangle.2.circlepath",
                text: "ショートカットとは別に「オートメーション」を設定すると、lifelifyを閉じるたびに壁紙を更新できます。毎回、手動で実行する必要はありません。"
            )
        case .automationOpen, .automationApp, .automationTiming, .automationShortcut, .automationConfirm:
            if let index = currentPage.automationIndex {
                automationContent(at: index)
            }
        case .complete:
            explanationContent(
                symbol: "checkmark.circle",
                text: "lifelifyで予定を変更したら、アプリを閉じてロック画面を確認してみてください。"
            )
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("好きな壁紙に予定を重ねて、毎日の予定をすぐに確認できるようにしましょう。")
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                overviewRow("壁紙を選ぶ", symbol: "photo")
                overviewRow("ロック画面に設定", symbol: "lock")
                overviewRow("自動で更新", symbol: "arrow.triangle.2.circlepath")
            }
        }
    }

    private func overviewRow(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func explanationContent(symbol: String, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, 12)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installationContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("ロック画面に予定を表示するショートカットを追加します。")
                .fixedSize(horizontal: false, vertical: true)

            instructionList([
                "下のボタンで追加画面を開きます。",
                "開いた画面で「ショートカットを追加」をタップします。",
                "追加できたら、lifelifyに戻って「次へ」をタップします。"
            ])

            Button(action: onInstall) {
                Label("ショートカットを追加", systemImage: "plus.app")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("wallpaperShortcut.install")
        }
    }

    private var verificationContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("追加したショートカットを一度動かして、壁紙が更新されることを確認します。")
                .fixedSize(horizontal: false, vertical: true)

            instructionList([
                "「ショートカットを開く」をタップします。",
                "「lifelify 壁紙カレンダー」をタップして実行します。",
                "許可を求められたら、内容を確認して許可します。",
                "ロック画面に予定が表示されたら、lifelifyに戻って「次へ」をタップします。"
            ])

            openShortcutsButton
        }
    }

    private func automationContent(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: "\(index + 1)/\(automationSteps.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("wallpaperShortcut.automationProgress")

            instructionList(automationSteps[index].instructions)

            if index == 0 {
                openShortcutsButton
            }

            Image(automationSteps[index].assetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 290)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("wallpaperShortcut.automationGuide")
    }

    private func instructionList(_ instructions: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                HStack(alignment: .top, spacing: 10) {
                    Text(verbatim: "\(index + 1).")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(instruction)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var openShortcutsButton: some View {
        Button(action: onOpenShortcuts) {
            Label("ショートカットを開く", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("wallpaperShortcut.open")
    }

    private var navigationControls: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 12) {
                if currentPage != .welcome {
                    Button(action: goBack) {
                        Text("戻る")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("wallpaperShortcut.back")
                }

                Button(action: advance) {
                    Text(nextButtonTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentPage.stage == 1 && isWallpaperLoading)
                .accessibilityIdentifier("wallpaperShortcut.next")
            }

            if currentPage.stage == 2 {
                NavigationLink {
                    ScrollView {
                        manualGuide()
                            .padding(20)
                    }
                    .navigationTitle("手動で設定")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Text("※ 追加できない場合は、手動で作成できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("wallpaperShortcut.manual")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(.background)
    }

    private var nextButtonTitle: LocalizedStringKey {
        switch currentPage {
        case .welcome: "はじめる"
        case .preview: "この壁紙で進む"
        case .automationConfirm: "設定を確認しました"
        case .complete: "閉じる"
        default: "次へ"
        }
    }

    private func advance() {
        guard !(currentPage.stage == 1 && isWallpaperLoading) else { return }
        // Opening or returning from another app never changes progress or implies success.
        if let nextPage = Page(rawValue: currentPage.rawValue + 1) {
            currentPage = nextPage
        } else {
            dismiss()
        }
    }

    private func goBack() {
        if let previousPage = Page(rawValue: currentPage.rawValue - 1) {
            currentPage = previousPage
        }
    }

    private struct AutomationStep {
        let assetName: String
        let instructions: [LocalizedStringKey]
    }

    private enum Page: Int {
        case welcome
        case background
        case layout
        case privacy
        case preview
        case shortcutIntro
        case shortcutInstall
        case shortcutVerify
        case automationIntro
        case automationOpen
        case automationApp
        case automationTiming
        case automationShortcut
        case automationConfirm
        case complete

        var stage: Int? {
            switch self {
            case .welcome, .complete: nil
            case .background, .layout, .privacy, .preview: 1
            case .shortcutIntro, .shortcutInstall, .shortcutVerify: 2
            default: 3
            }
        }

        var stageTitle: LocalizedStringKey {
            switch stage {
            case 1: "壁紙を作る"
            case 2: "ショートカットを追加"
            default: "自動更新を設定"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .welcome: "ロック画面で、予定をひと目に"
            case .background: "背景を選びましょう"
            case .layout: "表示する週数を選びましょう"
            case .privacy: "予定の見せ方を選びましょう"
            case .preview: "この壁紙でよろしいですか？"
            case .shortcutIntro: "壁紙の設定には、ショートカットを使います"
            case .shortcutInstall: "ショートカットを追加"
            case .shortcutVerify: "ロック画面を確認"
            case .automationIntro: "予定を自動で更新しましょう"
            case .automationOpen: "オートメーションを開く"
            case .automationApp: "アプリを選ぶ"
            case .automationTiming: "実行するタイミングを設定"
            case .automationShortcut: "ショートカットを選ぶ"
            case .automationConfirm: "設定を確認"
            case .complete: "設定できました"
            }
        }

        var automationIndex: Int? {
            guard rawValue >= Page.automationOpen.rawValue,
                  rawValue <= Page.automationConfirm.rawValue else { return nil }
            return rawValue - Page.automationOpen.rawValue
        }
    }
}

#Preview {
    WallpaperCalendarShortcutInstallGuide(onInstall: {}, onOpenShortcuts: {}) {
        EmptyView()
    } layoutContent: {
        EmptyView()
    } privacyContent: {
        EmptyView()
    } previewContent: {
        EmptyView()
    } manualGuide: {
        EmptyView()
    }
}
