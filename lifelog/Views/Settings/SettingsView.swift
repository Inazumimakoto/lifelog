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
    @StateObject private var appLockService = AppLockService.shared
    @State private var showMailComposer = false
    @State private var showMailErrorAlert = false
    @State private var showCalendarSettings = false
    @State private var showNotificationSettings = false
    @State private var showHelp = false
    @State private var showLetterList = false
    
    var body: some View {
        Form {
            // アプリ内設定
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
                
                Toggle(isOn: $appLockService.isAppLockEnabled) {
                    Label("アプリロック", systemImage: "lock.fill")
                        .foregroundStyle(.primary)
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
                
                Button {
                    showLetterList = true
                } label: {
                    HStack {
                        Label("未来への手紙", systemImage: "envelope.fill")
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
                        Label("lifelogの権限設定", systemImage: "gearshape.fill")
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
            } header: {
                Text("外部リンク")
            } footer: {
                Text("タップすると外部アプリやウェブサイトが開きます")
            }
            
            Section {
                Text("バージョン 1.5")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showMailComposer) {
            MailComposerView(
                subject: "lifelogご意見・不具合報告",
                recipients: ["inazumimakoto@gmail.com"], // 実際のサポートアドレスに変更する
                body: "\n\n\nデバイス: \(UIDevice.current.model)\niOSバージョン: \(UIDevice.current.systemVersion)\nアプリバージョン: 1.5"
            )
        }
        .alert("メールアカウントが設定されていません", isPresented: $showMailErrorAlert) {
            Button("OK") { }
        } message: {
            Text("メールアプリでアカウントを設定するか、support@example.com まで直接ご連絡ください。")
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
        .sheet(isPresented: $showNotificationSettings) {
            NavigationStack {
                NotificationSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") {
                                showNotificationSettings = false
                            }
                        }
                    }
            }
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
    }
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
