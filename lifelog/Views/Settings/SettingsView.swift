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
    
    var body: some View {
        Form {
            Section("カレンダー") {
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
            }
            
            Section("プライバシー") {
                Toggle(isOn: $appLockService.isAppLockEnabled) {
                    Label("アプリロック", systemImage: "lock.fill")
                }
            }
            
            Section("通知") {
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
            
            Section("ヘルスケア") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("ヘルスケア設定を開く", systemImage: "heart.fill")
                        .foregroundStyle(.primary)
                }
                
                Text("設定画面が開いたら「ヘルスケア」を選択して、データの読み書きを許可してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("サポート") {
                Button {
                    ReviewRequestManager.shared.requestReviewManually()
                } label: {
                    Label("このアプリを応援する", systemImage: "star.fill")
                        .foregroundStyle(.primary)
                }
                
                Button {
                    if MFMailComposeViewController.canSendMail() {
                        showMailComposer = true
                    } else {
                        showMailErrorAlert = true
                    }
                } label: {
                    Label("ご意見・不具合報告", systemImage: "envelope.fill")
                        .foregroundStyle(.primary)
                }
            }
            
            Section {
                Text("バージョン 1.4")
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
                body: "\n\n\nデバイス: \(UIDevice.current.model)\niOSバージョン: \(UIDevice.current.systemVersion)\nアプリバージョン: 1.4"
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
