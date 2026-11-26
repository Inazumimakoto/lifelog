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
    @State private var elapsed: TimeInterval = 0
    @State private var overlayOpacity: Double = 1

    var body: some View {
        let scheme = theme?.colorScheme ?? colorScheme
        let systemLogo = scheme == .dark ? AppIconPalette.primaryDark : AppIconPalette.primaryLight
        let stem = theme == nil ? AppTheme.color(hex: systemLogo.stemHex) : (scheme == .dark ? Color.white : Color.black)
        let accent = theme.map { $0.accent ?? Color(uiColor: .systemBlue) } ?? AppTheme.color(hex: systemLogo.accentHex)
        let outline = theme?.selectionIndicator ?? accent
        AnimatedLogo(
            elapsed: elapsed,
            background: theme?.background ?? Color("LaunchBackground"),
            stem: stem,
            accent: accent,
            outline: outline
        )
        .opacity(overlayOpacity)
        .task {
            await _Concurrency.Task.yield()
            guard !_Concurrency.Task.isCancelled else { return }
            startAnimation()
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

        let duration = AnimatedLogo.timeline.duration
        withAnimation(.linear(duration: duration)) {
            elapsed = duration
        } completion: {
            complete()
        }
    }

    private func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        onComplete()
    }

    private struct AnimatedLogo: View, Animatable {
        var elapsed: TimeInterval
        let background: Color
        let stem: Color
        let accent: Color
        let outline: Color

        var animatableData: TimeInterval {
            get { elapsed }
            set { elapsed = newValue }
        }

        struct Frame {
            var offset: CGFloat = 0
            var scale = CGSize(width: 1, height: 1)
            var reveal: CGFloat = 0
        }

        // Sample all three properties from one clock, including when a frame is late.
        static let timeline = KeyframeTimeline(initialValue: Frame()) {
            KeyframeTrack(\.scale) {
                LinearKeyframe(CGSize(width: 1.16, height: 0.8), duration: 0.07, timingCurve: .easeInOut)
                LinearKeyframe(CGSize(width: 0.86, height: 1.2), duration: 0.025, timingCurve: .easeIn)
                LinearKeyframe(CGSize(width: 1, height: 1), duration: 0.045, timingCurve: .easeOut)
                LinearKeyframe(CGSize(width: 0.92, height: 1.1), duration: 0.055, timingCurve: .easeIn)
                LinearKeyframe(CGSize(width: 1.12, height: 0.86), duration: 0.025, timingCurve: .easeOut)
                LinearKeyframe(CGSize(width: 1, height: 1), duration: 0.03, timingCurve: .easeInOut)
            }
            KeyframeTrack(\.offset) {
                LinearKeyframe(0, duration: 0.07)
                LinearKeyframe(-10, duration: 0.025, timingCurve: .easeIn)
                LinearKeyframe(-28, duration: 0.045, timingCurve: .easeOut)
                LinearKeyframe(0, duration: 0.055, timingCurve: .easeIn)
            }
            KeyframeTrack(\.reveal) {
                LinearKeyframe(0, duration: 0.25)
                LinearKeyframe(1, duration: 0.28, timingCurve: .bezier(
                    startControlPoint: UnitPoint(x: 0.32, y: 0),
                    endControlPoint: UnitPoint(x: 0.62, y: 1)
                ))
            }
        }

        var body: some View {
            let frame = Self.timeline.value(time: elapsed)
            let logoSize: CGFloat = 200
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
                    background

                    Path(AppIconArtwork.stem).applying(transform)
                        .fill(stem)
                        .frame(width: logoSize, height: logoSize)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    Circle()
                        .fill(accent)
                        .overlay { Circle().strokeBorder(outline, lineWidth: 1) }
                        .frame(width: bounds.width, height: bounds.height)
                        .scaleEffect(x: frame.scale.width, y: frame.scale.height, anchor: .bottom)
                        .position(x: dotPosition.x, y: dotPosition.y + frame.offset)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                // Cut the window through every splash layer so the underlying live
                // ContentView (or LockView) is visible, while the outside stays opaque.
                .modifier(CircularRevealModifier(
                    center: dotPosition,
                    initialRadius: bounds.width / 2,
                    finalRadius: revealRadius,
                    rimColor: outline,
                    progress: frame.reveal,
                    isRevealing: frame.reveal > 0
                ))
                .clipped()
            }
        }
    }

    private struct CircularRevealModifier: ViewModifier {
        var center: CGPoint
        var initialRadius: CGFloat
        var finalRadius: CGFloat
        var rimColor: Color
        var progress: CGFloat
        var isRevealing: Bool

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
