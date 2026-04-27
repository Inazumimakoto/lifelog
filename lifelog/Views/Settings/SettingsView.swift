//
//  SettingsView.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import SwiftUI
import MessageUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var monetization = MonetizationService.shared
    @StateObject private var appLockService = AppLockService.shared
    @State private var showMailComposer = false
    @State private var showMailErrorAlert = false
    @State private var showCalendarSettings = false
    @State private var showWallpaperCalendarSettings = false
    @State private var showNotificationSettings = false
    @State private var showHelp = false
    @State private var showLetterList = false
    @State private var showLetterSharing = false
    @AppStorage("isDiaryTextHidden") private var isDiaryTextHidden: Bool = false
    @AppStorage("requiresDiaryOpenAuthentication") private var requiresDiaryOpenAuthentication: Bool = false
    @AppStorage("isMemoTextHidden") private var isMemoTextHidden: Bool = false
    @AppStorage("requiresMemoOpenAuthentication") private var requiresMemoOpenAuthentication: Bool = false
    @AppStorage("githubUsername") private var githubUsername: String = ""
    @State private var githubPAT: String = ""
    @State private var showPATHelp = false
    @State private var showPaywall = false
    @State private var premiumAlertMessage: String?
    @State private var showOptimizeConfirm = false
    @State private var isOptimizing = false
    @State private var optimizeCurrent: Int = 0
    @State private var optimizeTotal: Int = 0
    @State private var optimizeResult: String?
    @State private var currentStorageSize: Int64 = 0
#if DEBUG
    private let debugAutomaticStorefront = "AUTO"
#endif
    @StateObject private var githubService = GitHubService.shared
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        Form {
            appSettingsSection
            
            // ストレージ
            Section {
                Button {
                    showOptimizeConfirm = true
                } label: {
                    HStack {
                        Label("ストレージ最適化", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
                        Spacer()
                        if currentStorageSize > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: currentStorageSize, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .disabled(isOptimizing)
            } header: {
                Text("ストレージ")
            } footer: {
                Text("写真をJPEG圧縮して容量を削減します（解像度は変わりません）")
            }
            
            // ヘルプ
            Section("ヘルプ") {
                Button {
                    showHelp = true
                } label: {
                    HStack {
                        Label("使い方", systemImage: "questionmark.circle.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            
            // 外部リンク
            Section {
                Button {
                    // lifelogのアプリ設定を開く（位置情報・カレンダー等）
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("lifelifyの権限設定", systemImage: "gearshape.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                
                Button {
                    // ヘルスケアアプリを直接開く
                    if let url = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("ヘルスケアアプリを開く", systemImage: "heart.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                
                Button {
                    ReviewRequestManager.shared.requestReviewManually()
                } label: {
                    HStack {
                        Label("このアプリを応援する", systemImage: "star.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                
                Button {
                    if MFMailComposeViewController.canSendMail() {
                        showMailComposer = true
                    } else {
                        showMailErrorAlert = true
                    }
                } label: {
                    HStack {
                        Label("ご意見・不具合報告", systemImage: "envelope.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                
                Link(destination: URL(string: "https://inazumimakoto.github.io/lifelog-support/")!) {
                    HStack {
                        Label("プライバシーポリシー", systemImage: "lock.shield.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                
                Link(destination: URL(string: "https://github.com/Inazumimakoto/lifelog")!) {
                    HStack {
                        Label("ソースコード", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Text("MIT License")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("外部リンク")
            } footer: {
                Text("タップすると外部アプリやウェブサイトが開きます")
            }
            
            Section {
                Text("バージョン \(appVersion)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
            
            // ひみつの機能（一番下に配置）
            Section("ひみつの機能 🤫") {
                Button {
                    openLetterFeatureIfNeeded { showLetterList = true }
                } label: {
                    HStack {
                        Label("未来への手紙", systemImage: "envelope.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                
                Button {
                    openLetterFeatureIfNeeded { showLetterSharing = true }
                } label: {
                    HStack {
                        Label("大切な人への手紙", systemImage: "envelope.badge.person.crop")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            
            // 開発者向け
            Section {
                HStack {
                    Label("GitHubユーザー名", systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    TextField("username", text: $githubUsername)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Personal Access Token", systemImage: "key.fill")
                    
                    Button {
                        showPATHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    SecureField("未設定", text: $githubPAT)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .onChange(of: githubPAT) { _, newValue in
                            if !newValue.isEmpty {
                                githubService.savePAT(newValue)
                            }
                        }
                }
                
                if githubService.getPAT() != nil {
                    Button(role: .destructive) {
                        githubService.deletePAT()
                        githubPAT = ""
                    } label: {
                        Label("PATを削除", systemImage: "trash")
                    }
                }

#if DEBUG
                Picker("課金テスト国", selection: debugStorefrontSelectionBinding) {
                    Text("自動").tag(debugAutomaticStorefront)
                    Text("日本 (JP)").tag("JP")
                    Text("米国 (US)").tag("US")
                    Text("英国 (GB)").tag("GB")
                }

                Toggle("プレミアム強制ON", isOn: debugForcePremiumBinding)

                Text("Debugビルド専用。日本にいても海外/課金状態のUIを即テストできます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#endif
            } header: {
                Text("開発者向け 🧑‍💻")
            } footer: {
                Text("PATを設定すると正確なコントリビューション数が取得できます")
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isDiaryTextHidden) { _, newValue in
            if newValue == false {
                requiresDiaryOpenAuthentication = false
            }
        }
        .onChange(of: isMemoTextHidden) { _, newValue in
            if newValue == false {
                requiresMemoOpenAuthentication = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showMailComposer) {
            MailComposerView(
                subject: "lifelifyご意見・不具合報告",
                recipients: ["inazumimakoto@gmail.com"], // 実際のサポートアドレスに変更する
                body: "\n\n\nデバイス: \(UIDevice.current.model)\niOSバージョン: \(UIDevice.current.systemVersion)\nアプリバージョン: \(appVersion)"
            )
        }
        .alert("メールアカウントが設定されていません", isPresented: $showMailErrorAlert) {
            Button("OK") { }
        } message: {
            Text("メールアプリでアカウントを設定するか、inazumimakoto@gmail.com まで直接ご連絡ください。")
        }
        .alert("GitHub Personal Access Token", isPresented: $showPATHelp) {
            Button("閉じる") { }
            Button("GitHubを開く") {
                if let url = URL(string: "https://github.com/settings/tokens/new?description=lifelog&scopes=read:user") {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("""
            1. GitHubにログイン
            2. Settings → Developer settings → Personal access tokens → Tokens (classic)
            3. Generate new token (classic)
            4. Expiration: 任意
            5. Scope: read:user にチェック
            6. 生成されたトークンをコピー
            7. このアプリに貼り付け
            """)
        }
        .sheet(isPresented: $showCalendarSettings) {
            NavigationStack {
                CalendarCategorySettingsView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") {
                                showCalendarSettings = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showWallpaperCalendarSettings) {
            NavigationStack {
                WallpaperCalendarSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") {
                                showWallpaperCalendarSettings = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsSheet(isPresented: $showNotificationSettings)
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .sheet(isPresented: $showLetterList) {
            NavigationStack {
                LetterListView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") {
                                showLetterList = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showLetterSharing) {
            LetterSharingView()
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
        }
        .alert("プレミアム機能", isPresented: Binding(
            get: { premiumAlertMessage != nil },
            set: { if $0 == false { premiumAlertMessage = nil } }
        )) {
            Button("プランを見る") {
                showPaywall = true
            }
            Button("あとで", role: .cancel) { }
        } message: {
            Text(premiumAlertMessage ?? "")
        }
        .alert("ストレージ最適化", isPresented: $showOptimizeConfirm) {
            Button("最適化する") {
                startOptimization()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("既存の写真をJPEG圧縮して容量を削減します。解像度は変わりません。この処理は数分かかる場合があります。")
        }
        .alert("最適化完了", isPresented: Binding(
            get: { optimizeResult != nil },
            set: { if $0 == false { optimizeResult = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(optimizeResult ?? "")
        }
        .overlay {
            if isOptimizing {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("写真を最適化中...")
                            .font(.headline)
                        if optimizeTotal > 0 {
                            Text("\(optimizeCurrent) / \(optimizeTotal)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .onAppear {
            currentStorageSize = PhotoStorage.totalStorageSize()
        }
    }

    private var appSettingsSection: some View {
        Section("アプリ設定") {
            Button {
                showCalendarSettings = true
            } label: {
                HStack {
                    Label("カレンダー連携", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            Button {
                showWallpaperCalendarSettings = true
            } label: {
                HStack {
                    Label("ロック画面カレンダー", systemImage: "rectangle.stack.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            
            Toggle(isOn: $appLockService.isAppLockEnabled) {
                Label("アプリロック", systemImage: "lock.fill")
                    .foregroundStyle(.primary)
            }

            Toggle(isOn: $isDiaryTextHidden) {
                Label("日記本文を非表示", systemImage: "eye.slash")
                    .foregroundStyle(.primary)
            }

            if isDiaryTextHidden {
                Toggle(isOn: $requiresDiaryOpenAuthentication) {
                    Label("日記を開くときに認証", systemImage: "lock.shield")
                        .foregroundStyle(.primary)
                }
            }

            Toggle(isOn: $isMemoTextHidden) {
                Label("メモ本文を非表示", systemImage: "eye.slash")
                    .foregroundStyle(.primary)
            }

            if isMemoTextHidden {
                Toggle(isOn: $requiresMemoOpenAuthentication) {
                    Label("メモを開くときに認証", systemImage: "lock.shield")
                        .foregroundStyle(.primary)
                }
            }
            
            Button {
                showNotificationSettings = true
            } label: {
                HStack {
                    Label("通知設定", systemImage: "bell.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func openLetterFeatureIfNeeded(_ openAction: () -> Void) {
        guard monetization.canUseLetters else {
            premiumAlertMessage = monetization.lettersMessage()
            return
        }
        openAction()
    }

    private func startOptimization() {
        isOptimizing = true
        optimizeCurrent = 0
        optimizeTotal = 0
        
        // Use qualified name to avoid conflict with `Models.Task`
        _Concurrency.Task { @MainActor in
            let sizeBefore = PhotoStorage.totalStorageSize()
            
            _ = await PhotoStorage.optimizeExistingPhotos { current, total, _ in
                // Use _Concurrency.Task to avoid shadowing by Models.Task
                _Concurrency.Task { @MainActor in
                    self.optimizeCurrent = current
                    self.optimizeTotal = total
                }
            }
            
            let sizeAfter = PhotoStorage.totalStorageSize()
            let saved = max(0, sizeBefore - sizeAfter)
            
            self.isOptimizing = false
            self.currentStorageSize = sizeAfter
            
            if saved > 0 {
                let savedStr = ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)
                let afterStr = ByteCountFormatter.string(fromByteCount: sizeAfter, countStyle: .file)
                self.optimizeResult = "\(savedStr) 削減しました（現在: \(afterStr)）"
            } else {
                self.optimizeResult = "すでに最適化済みです"
            }
        }
    }

#if DEBUG
    private var debugStorefrontSelectionBinding: Binding<String> {
        Binding(
            get: {
                monetization.debugStorefrontCountryCode ?? debugAutomaticStorefront
            },
            set: { newValue in
                let code: String? = (newValue == debugAutomaticStorefront) ? nil : newValue
                monetization.applyDebugStorefrontCountryCode(code)
            }
        )
    }

    private var debugForcePremiumBinding: Binding<Bool> {
        Binding(
            get: { monetization.debugForcePremiumEntitlement },
            set: { monetization.applyDebugForcePremiumEntitlement($0) }
        )
    }
#endif
}

// メール作成用のラッパーView
struct MailComposerView: UIViewControllerRepresentable {
    let subject: String
    let recipients: [String]?
    let body: String
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setSubject(subject)
        composer.setToRecipients(recipients)
        composer.setMessageBody(body, isHTML: false)
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        
        init(_ parent: MailComposerView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
        }
    }
}

private struct NotificationSettingsSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            NotificationSettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") {
                            isPresented = false
                        }
                    }
                }
        }
    }
}
