import SwiftUI

/// Uses the launch storyboard's logo geometry, with the app's current theme.
/// See docs/ui-guidelines.md §起動時の表示.
struct StartupLogoView: View {
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasStarted = false
    @State private var hasCompleted = false
    @State private var dotOffset: CGFloat = 0
    @State private var dotScale = CGSize(width: 1, height: 1)
    @State private var isRevealing = false
    @State private var revealProgress: CGFloat = 0
    @State private var overlayOpacity: Double = 1

    private let logoSize: CGFloat = 200

    var body: some View {
        let scheme = theme?.colorScheme ?? colorScheme
        let systemLogo = scheme == .dark ? AppIconPalette.primaryDark : AppIconPalette.primaryLight
        let stem = theme == nil ? AppTheme.color(hex: systemLogo.stemHex) : (scheme == .dark ? Color.white : Color.black)
        let accent = theme.map { $0.accent ?? Color(uiColor: .systemBlue) } ?? AppTheme.color(hex: systemLogo.accentHex)
        let outline = theme?.selectionIndicator ?? accent
        let scale = logoSize / AppIconArtwork.dimension
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        GeometryReader { geometry in
            let bounds = AppIconArtwork.dotBounds.applying(transform)
            let dotPosition = CGPoint(
                x: geometry.size.width / 2 + bounds.midX - logoSize / 2,
                y: geometry.size.height / 2 + bounds.midY - logoSize / 2
            )
            let revealRadius = hypot(
                max(dotPosition.x, geometry.size.width - dotPosition.x),
                max(dotPosition.y, geometry.size.height - dotPosition.y)
            ) + 2

            ZStack {
                (theme?.background ?? Color("LaunchBackground"))

                Path(AppIconArtwork.stem).applying(transform)
                    .fill(stem)
                    .frame(width: logoSize, height: logoSize)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                Circle()
                    .fill(accent)
                    .overlay { Circle().strokeBorder(outline, lineWidth: 1) }
                    .frame(width: bounds.width, height: bounds.height)
                    .scaleEffect(x: dotScale.width, y: dotScale.height, anchor: .bottom)
                    .position(x: dotPosition.x, y: dotPosition.y + dotOffset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // Cut the window through every splash layer so the underlying live
            // ContentView (or LockView) is visible, while the outside stays opaque.
            .modifier(CircularRevealModifier(
                center: dotPosition,
                initialRadius: bounds.width / 2,
                finalRadius: revealRadius,
                rimColor: outline,
                progress: revealProgress,
                isRevealing: isRevealing
            ))
            .opacity(overlayOpacity)
            .clipped()
            .task {
                // Let the themed first frame enter the view tree before animating.
                await _Concurrency.Task.yield()
                guard !_Concurrency.Task.isCancelled else { return }
                startAnimation()
            }
        }
        .environment(\.colorScheme, scheme)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                complete()
            }
        }
    }

    private func startAnimation() {
        guard !hasStarted, !hasCompleted else { return }
        hasStarted = true

        if reduceMotion {
            withAnimation(.linear(duration: 0.1)) {
                overlayOpacity = 0
            } completion: {
                complete()
            }
            return
        }

        // Keep the lower edge planted while squashing to anticipate the jump.
        withAnimation(.easeInOut(duration: 0.07)) {
            dotScale = CGSize(width: 1.16, height: 0.8)
        } completion: {
            takeOff()
        }
    }

    private func takeOff() {
        guard !hasCompleted else { return }
        // A quick stretch releases the stored energy, then the rise slows down.
        withAnimation(.easeIn(duration: 0.025)) {
            dotOffset = -10
            dotScale = CGSize(width: 0.86, height: 1.2)
        } completion: {
            rise()
        }
    }

    private func rise() {
        guard !hasCompleted else { return }
        withAnimation(.easeOut(duration: 0.045)) {
            dotOffset = -28
            dotScale = CGSize(width: 1, height: 1)
        } completion: {
            land()
        }
    }

    private func land() {
        guard !hasCompleted else { return }
        withAnimation(.easeIn(duration: 0.055)) {
            dotOffset = 0
            dotScale = CGSize(width: 0.92, height: 1.1)
        } completion: {
            absorbLanding()
        }
    }

    private func absorbLanding() {
        guard !hasCompleted else { return }
        withAnimation(.easeOut(duration: 0.025)) {
            dotScale = CGSize(width: 1.12, height: 0.86)
        } completion: {
            settle()
        }
    }

    private func settle() {
        guard !hasCompleted else { return }
        withAnimation(.easeInOut(duration: 0.03)) {
            dotScale = CGSize(width: 1, height: 1)
        } completion: {
            revealUI()
        }
    }

    private func revealUI() {
        guard !hasCompleted else { return }
        // Open only after landing has recovered its round shape. One modifier
        // interpolates both the aperture and its rim so they stay aligned.
        isRevealing = true
        withAnimation(.timingCurve(0.32, 0, 0.62, 1, duration: 0.28)) {
            revealProgress = 1
        } completion: {
            complete()
        }
    }

    private func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        onComplete()
    }

    private struct CircularRevealModifier: AnimatableModifier {
        var center: CGPoint
        var initialRadius: CGFloat
        var finalRadius: CGFloat
        var rimColor: Color
        var progress: CGFloat
        var isRevealing: Bool

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let radius = initialRadius + (finalRadius - initialRadius) * progress

            content
                .compositingGroup()
                .mask {
                    CircularRevealMask(center: center, radius: radius, isRevealing: isRevealing)
                        .fill(style: FillStyle(eoFill: true))
                }
                .overlay {
                    if isRevealing {
                        Circle()
                            .stroke(rimColor.opacity(0.75), lineWidth: 1.5)
                            .frame(width: radius * 2, height: radius * 2)
                            .position(center)
                            .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                            // Fade the rim as it leaves the screen, including
                            // its shadow, before removing the splash overlay.
                            .opacity(1 - Double(progress * progress * progress))
                    }
                }
        }
    }

    private struct CircularRevealMask: Shape {
        var center: CGPoint
        var radius: CGFloat
        var isRevealing: Bool

        func path(in rect: CGRect) -> Path {
            Path { path in
                path.addRect(rect)
                if isRevealing {
                    path.addEllipse(in: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemBackground)
        StartupLogoView(onComplete: {})
    }
}
