import SwiftUI
import UserNotifications

/// Keep the saved preference intact while iOS handles a user-initiated opt-in.
struct NotificationPermissionToggle: View {
    private let title: LocalizedStringKey
    @Binding private var isOn: Bool
    @State private var requesting = false

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { enabled in
            if enabled {
                requesting = true
            } else {
                isOn = false
            }
        }))
        .disabled(requesting)
        .notificationPermissionRequest($requesting) { isOn = true }
    }
}

extension View {
    func notificationPermissionRequest(_ requesting: Binding<Bool>, onAuthorized: @escaping () -> Void) -> some View {
        modifier(NotificationPermissionRequest(requesting: requesting, onAuthorized: onAuthorized))
    }
}

private struct NotificationPermissionRequest: ViewModifier {
    @Binding var requesting: Bool
    let onAuthorized: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var problem: UNAuthorizationStatus?

    func body(content: Content) -> some View {
        content
            .task(id: requesting) {
                guard requesting else { return }
                let status = await NotificationService.shared.authorizationForUserAction()
                guard !_Concurrency.Task.isCancelled else { return }
                requesting = false
                switch status {
                case .authorized, .provisional, .ephemeral:
                    onAuthorized()
                default:
                    problem = status
                }
            }
            .onDisappear { requesting = false }
            .alert(
                problem == .denied
                    ? Text("notifications.deniedTitle", tableName: "ContextualPermissions")
                    : Text("notifications.unavailableTitle", tableName: "ContextualPermissions"),
                isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }),
                presenting: problem
            ) { status in
                if status == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        Text("notifications.openSettings", tableName: "ContextualPermissions")
                    }
                    Button("キャンセル", role: .cancel) { }
                } else {
                    Button("OK", role: .cancel) { }
                }
            } message: { status in
                if status == .denied {
                    Text("notifications.deniedMessage", tableName: "ContextualPermissions")
                } else {
                    Text("notifications.unavailableMessage", tableName: "ContextualPermissions")
                }
            }
    }
}
