import SwiftUI

/// docs/ui-guidelines.md: first-run permissions are optional, one choice at a time.
struct InitialPermissionsSetupView: View {
    let store: AppDataStore
    let onComplete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var weatherService = WeatherService()
    @State private var currentStep: InitialPermissionStep = .notifications
    @State private var requestedStep: InitialPermissionStep?
    @State private var hasFinished = false
    @AccessibilityFocusState private var focusedStep: InitialPermissionStep?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    progressHeader
                    Spacer(minLength: 0)
                    permissionDetails
                    Spacer(minLength: 0)
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(currentStep)
        }
        .clipped()
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onChange(of: currentStep) { _, step in focusedStep = step }
        .task(id: requestedStep) {
            guard let step = requestedStep else { return }
            await requestPermission(for: step)
            guard !_Concurrency.Task.isCancelled, requestedStep == step, !hasFinished else { return }
            advance()
        }
    }

    private var progressHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("setup.title", tableName: "FirstRunPermissions")
                        .font(.headline)
                    Text("progress \(currentStep.rawValue + 1)/\(InitialPermissionStep.allCases.count)", tableName: "FirstRunPermissions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                if !dynamicTypeSize.isAccessibilitySize { Spacer() }

                Button(action: finish) {
                    Text("action.skipAll", tableName: "FirstRunPermissions")
                        .frame(minHeight: 44)
                }
                .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 8) {
                ForEach(InitialPermissionStep.allCases) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? step.tint : Color(.systemGray4))
                        .frame(height: 5)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var permissionDetails: some View {
        VStack(spacing: 16) {
            Image(systemName: currentStep.symbol)
                .font(.largeTitle.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(currentStep.tint)
                .padding(18)
                .background(currentStep.tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            Text(currentStep.title, tableName: "FirstRunPermissions")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedStep, equals: currentStep)
            Text(currentStep.purpose, tableName: "FirstRunPermissions")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(currentStep.examples.enumerated()), id: \.offset) { _, example in
                    Label {
                        Text(example, tableName: "FirstRunPermissions")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                requestedStep = currentStep
            } label: {
                Group {
                    if requestedStep == currentStep {
                        Text("action.working", tableName: "FirstRunPermissions")
                    } else {
                        Text("action.continue", tableName: "FirstRunPermissions")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(requestedStep != nil)

            Button(action: advance) {
                Text("action.later", tableName: "FirstRunPermissions")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private func advance() {
        guard !hasFinished else { return }
        requestedStep = nil
        if let next = InitialPermissionStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        } else {
            finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        requestedStep = nil
        onComplete()
    }

    private func requestPermission(for step: InitialPermissionStep) async {
        switch step {
        case .notifications:
            _ = await NotificationService.shared.authorizationForUserAction()
        case .location:
            _ = await weatherService.requestLocationPermissionForSetup()
        case .calendar:
            if await CalendarEventService().requestAccessIfNeeded(shouldPrompt: true) {
                _ = await store.syncExternalCalendarsIfAuthorized()
            }
        case .health:
            _ = await store.loadHealthData(requestAuthorizationIfNeeded: true)
        }
    }
}

private enum InitialPermissionStep: Int, CaseIterable, Identifiable {
    case notifications, location, calendar, health
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .notifications: "notifications.title"
        case .location: "location.title"
        case .calendar: "calendar.title"
        case .health: "health.title"
        }
    }

    var purpose: LocalizedStringKey {
        switch self {
        case .notifications: "notifications.purpose"
        case .location: "location.purpose"
        case .calendar: "calendar.purpose"
        case .health: "health.purpose"
        }
    }

    var examples: [LocalizedStringKey] {
        switch self {
        case .notifications: ["notifications.example1", "notifications.example2", "notifications.example3"]
        case .location: ["location.example1", "location.example2", "location.example3"]
        case .calendar: ["calendar.example1", "calendar.example2", "calendar.example3"]
        case .health: ["health.example1", "health.example2", "health.example3"]
        }
    }

    var symbol: String {
        switch self {
        case .notifications: "bell.badge.fill"
        case .location: "location.circle.fill"
        case .calendar: "calendar.badge.clock"
        case .health: "heart.text.square.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notifications: .orange
        case .location: .green
        case .calendar: .blue
        case .health: .pink
        }
    }
}
