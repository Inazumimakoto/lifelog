#if DEBUG
import AuthenticationServices
import SwiftUI

/// Account setup and app-based OAuth consent share one modal so an incoming link is not lost
/// when the user returns from ChatGPT while this screen is already presented.
struct ShoppingConnectionView: View {
    @ObservedObject var service: ShoppingConnectionService
    @ObservedObject var sync: ShoppingSyncService
    @Environment(\.dismiss) private var dismiss
    var restoresSession = true

    var body: some View {
        Group {
            if let requestID = service.approvalRequestID {
                ShoppingApprovalView(service: service, requestID: requestID)
                    .id(requestID)
            } else {
                Form {
                    ShoppingConnectionDisclosure()
                    ShoppingConnectionAccountSection(service: service)
                    if service.accountID != nil {
                        ShoppingSyncSection(sync: sync)
                        Section("shopping.connection.next") {
                            Text("shopping.connection.next.body")
                            ShoppingChatGPTOpenButtons()
                        }
                        Section {
                            Button("shopping.connection.logout", role: .destructive) {
                                _Concurrency.Task { await service.logout() }
                            }
                            .disabled(service.isBusy)
                        } footer: {
                            Text("shopping.connection.logout.note")
                        }
                    }
                }
            }
        }
        .navigationTitle("shopping.connection.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("shopping.connection.close") { dismiss() }
            }
        }
        .task {
            if restoresSession { await service.restoreSession() }
        }
    }
}

private struct ShoppingConnectionDisclosure: View {
    var body: some View {
        Section {
            Label("shopping.connection.prototype", systemImage: "hammer")
                .font(.headline)
            Text("shopping.connection.prototype.body")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShoppingConnectionAccountSection: View {
    @ObservedObject var service: ShoppingConnectionService
    @Environment(\.colorScheme) private var colorScheme
    @State private var acceptsAccountCreation = false

    var body: some View {
        Section("shopping.connection.account") {
            if let accountID = service.accountID {
                Label("shopping.connection.signedin", systemImage: "person.crop.circle.badge.checkmark")
                Text(verbatim: accountID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text("shopping.connection.account.id"))
                    .accessibilityValue(Text(verbatim: accountID))
            } else {
                Text("shopping.connection.account.body")
                Toggle("shopping.connection.account.consent", isOn: $acceptsAccountCreation)
                    .disabled(service.isBusy)
                if acceptsAccountCreation {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let challenge = service.challenge, challenge.isUsable || service.isBusy {
                            SignInWithAppleButton(.continue, onRequest: service.configureAppleRequest) { result in
                                _Concurrency.Task { await service.finishAppleSignIn(result) }
                            }
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 50)
                            .disabled(service.isBusy)
                            .accessibilityIdentifier("shopping.connection.apple")
                        } else if !service.isBusy {
                            Button("shopping.connection.prepare") {
                                _Concurrency.Task { await service.prepareAppleChallenge() }
                            }
                        }
                    }
                }
            }
            if service.isBusy { ProgressView("shopping.connection.loading") }
            if let error = service.errorMessage {
                Text(verbatim: error).foregroundStyle(.red)
                Button("shopping.connection.retry") {
                    _Concurrency.Task {
                        await service.restoreSession()
                        if acceptsAccountCreation { await service.prepareAppleChallenge() }
                    }
                }
                .disabled(service.isBusy)
            }
        }
        .task(id: acceptsAccountCreation) {
            if acceptsAccountCreation { await service.prepareAppleChallenge() }
        }
    }
}

private struct ShoppingApprovalView: View {
    @ObservedObject var service: ShoppingConnectionService
    let requestID: String
    @ObservedObject private var appLock = AppLockService.shared
    @State private var request: ShoppingConnectionService.ApprovalRequest?
    @State private var loadedAccountID: String?
    @State private var isLoading = false
    @State private var isDeciding = false
    @State private var decision: ShoppingConnectionService.Decision?
    @State private var errorMessage: String?
    @State private var outcomeUncertain = false
    @State private var browserOpeningFailed = false

    var body: some View {
        Form {
            ShoppingConnectionDisclosure()
            ShoppingConnectionAccountSection(service: service)
            if let decision {
                Section {
                    Label {
                        Text(decision == .approve ? LocalizedStringKey("shopping.connection.approved") : LocalizedStringKey("shopping.connection.denied"))
                    } icon: {
                        Image(systemName: decision == .approve ? "checkmark.circle" : "xmark.circle")
                    }
                    Text("shopping.connection.return.body")
                    Button("shopping.connection.return.open", systemImage: "safari") {
                        _Concurrency.Task { await returnToBrowser() }
                    }
                    if browserOpeningFailed {
                        Text("shopping.connection.return.manual").foregroundStyle(.secondary)
                    }
                }
            } else if outcomeUncertain {
                Section {
                    Text("shopping.connection.uncertain")
                    Text("shopping.connection.return.body")
                }
            } else if service.accountID == nil {
                Section { Text("shopping.connection.approval.signin") }
            } else {
                approvalSections
            }
        }
        .task(id: service.accountID) { await load() }
        .onChange(of: appLock.isUnlocked) { _, unlocked in
            if unlocked && request == nil && decision == nil && !outcomeUncertain {
                _Concurrency.Task { await load() }
            }
        }
        .interactiveDismissDisabled(isDeciding)
    }

    @ViewBuilder
    private var approvalSections: some View {
        if isLoading { Section { ProgressView("shopping.connection.loading") } }
        if let errorMessage {
            Section {
                Text(verbatim: errorMessage).foregroundStyle(.red)
                Button("shopping.connection.retry") { _Concurrency.Task { await load() } }
                    .disabled(isLoading || isDeciding)
            }
        }
        if let request, let loadedAccountID {
            Section("shopping.connection.requester") {
                Text(verbatim: request.client_name).font(.headline)
                if request.client_domain.isEmpty {
                    Text("shopping.connection.client.reported").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: request.client_domain).font(.subheadline).textSelection(.enabled)
                }
                LabeledContent("shopping.connection.callback") {
                    Text(verbatim: request.callback_host)
                }
            }
            Section("shopping.connection.permissions") {
                ForEach(request.scopes, id: \.self) { scope in
                    switch scope {
                    case "shopping:read": Label("shopping.connection.scope.read", systemImage: "eye")
                    case "shopping:write": Label("shopping.connection.scope.write", systemImage: "pencil")
                    case "offline_access": Label("shopping.connection.scope.offline", systemImage: "arrow.triangle.2.circlepath")
                    default: EmptyView()
                    }
                }
            }
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        if request.isExpired {
                            Text("shopping.connection.error.expired").foregroundStyle(.red)
                        } else {
                            Text("shopping.connection.approval.confirm")
                            Text("shopping.connection.approval.ownrequest")
                                .font(.callout)
                            Button("shopping.connection.approve", systemImage: "checkmark") {
                                submit(.approve, request: request, accountID: loadedAccountID)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("shopping.connection.approve")
                            Button("shopping.connection.deny", role: .destructive) {
                                submit(.deny, request: request, accountID: loadedAccountID)
                            }
                            .accessibilityIdentifier("shopping.connection.deny")
                        }
                        if isDeciding { ProgressView("shopping.connection.loading") }
                    }
                    .disabled(isDeciding || service.isBusy || service.accountID != loadedAccountID || (appLock.isAppLockEnabled && !appLock.isUnlocked))
                }
            }
        }
    }

    private func load() async {
        guard let accountID = service.accountID, !isLoading, !isDeciding, decision == nil, !outcomeUncertain else { return }
        request = nil
        loadedAccountID = nil
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.loadApproval(id: requestID)
            guard !_Concurrency.Task.isCancelled, service.accountID == accountID else { return }
            request = result
            loadedAccountID = accountID
        } catch {
            guard !_Concurrency.Task.isCancelled else { return }
            errorMessage = service.localizedMessage(for: error)
        }
    }

    private func submit(_ choice: ShoppingConnectionService.Decision,
                        request: ShoppingConnectionService.ApprovalRequest, accountID: String) {
        guard !isDeciding else { return }
        isDeciding = true
        errorMessage = nil
        _Concurrency.Task {
            defer { isDeciding = false }
            do {
                try await service.decide(choice, request: request, accountID: accountID)
                decision = choice
                await returnToBrowser()
            } catch {
                // A timeout can happen after the server accepted consent. Avoid offering another mutation.
                if error is URLError {
                    outcomeUncertain = true
                    self.request = nil
                } else {
                    errorMessage = service.localizedMessage(for: error)
                    self.request = nil
                }
            }
        }
    }

    private func returnToBrowser() async {
        guard let url = ShoppingConnectionService.resumeURL(for: requestID) else {
            browserOpeningFailed = true
            return
        }
        browserOpeningFailed = !(await UIApplication.shared.open(url, options: [:]))
    }
}

private struct ShoppingSyncSection: View {
    @ObservedObject var sync: ShoppingSyncService

    var body: some View {
        Section("shopping.sync.title") {
            if !sync.isEnabled {
                Text("shopping.sync.initial.body")
                Button("shopping.sync.enable", systemImage: "icloud.and.arrow.up") {
                    _Concurrency.Task { await sync.enable() }
                }
            } else {
                Text("shopping.sync.enabled.body")
                if let date = sync.lastSyncedAt {
                    LabeledContent("shopping.sync.last") { Text(date, style: .time) }
                }
                Button("shopping.sync.now", systemImage: "arrow.triangle.2.circlepath") {
                    _Concurrency.Task { await sync.synchronize() }
                }
            }
            if sync.isSyncing { ProgressView("shopping.sync.progress") }
            if let error = sync.errorMessage { Text(verbatim: error).foregroundStyle(.red) }
            if let conflict = sync.conflict {
                if conflict.response.error == "place_unavailable" {
                    Text("shopping.sync.conflict.place")
                    Button("shopping.sync.conflict.unassign") {
                        _Concurrency.Task { await sync.resolveUnavailablePlace() }
                    }
                } else {
                    Text("shopping.sync.conflict.body").font(.headline)
                    if let record = conflict.response.record {
                        switch record.data {
                        case .item(let data): Text(verbatim: data.title + (data.note.isEmpty ? "" : "\n" + data.note))
                        case .place(let data): Text(verbatim: data.name)
                        }
                        if record.isDeleted { Text("shopping.sync.conflict.deleted") }
                    } else { Text("shopping.sync.conflict.deleted") }
                    Button("shopping.sync.conflict.remote") {
                        _Concurrency.Task { await sync.resolveConflict(keepLocal: false) }
                    }
                    Button("shopping.sync.conflict.local") {
                        _Concurrency.Task { await sync.resolveConflict(keepLocal: true) }
                    }
                }
            }
        }
        .disabled(sync.isSyncing)
    }
}

private struct ShoppingChatGPTOpenButtons: View {
    @State private var manualOpeningNeeded = false

    var body: some View {
        Button("shopping.connection.openapp", systemImage: "arrow.up.forward.app") {
            _Concurrency.Task { @MainActor in
                let opened = await UIApplication.shared.open(ShoppingConnectionService.pluginURL,
                                                            options: [.universalLinksOnly: true])
                manualOpeningNeeded = !opened
            }
        }
        if manualOpeningNeeded {
            Text("shopping.connection.open.manual").foregroundStyle(.secondary)
        }
        Button("shopping.connection.openweb", systemImage: "safari") {
            _Concurrency.Task { @MainActor in
                // Use normal HTTPS handling instead of introducing an embedded browser cookie session.
                // iOS and ChatGPT still decide whether the destination opens in an app or a browser.
                manualOpeningNeeded = !(await UIApplication.shared.open(ShoppingConnectionService.pluginURL, options: [:]))
            }
        }
    }
}

#Preview("Connection setup") {
    let connection = ShoppingConnectionService()
    let store = ShoppingStore(container: PersistenceController(inMemory: true).container, supportsShoppingSync: true)
    NavigationStack {
        ShoppingConnectionView(service: connection, sync: ShoppingSyncService(store: store, transport: connection), restoresSession: false)
    }
}
#endif
