import SwiftUI

/// Shared downward-dismiss motion; each viewer keeps its own paging and photo actions.
struct DismissiblePhotoViewer<Content: View>: View {
    let isZoomed: Bool
    let onDismiss: () -> Void
    private let content: Content
    @State private var verticalDragOffset: CGFloat = 0
    private let dismissDragThreshold: CGFloat = 140

    init(isZoomed: Bool,
         onDismiss: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.isZoomed = isZoomed
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            content
                .offset(y: verticalDragOffset)
        }
        .simultaneousGesture(verticalDismissGesture)
    }

    private var backgroundOpacity: Double {
        let progress = min(max(verticalDragOffset / dismissDragThreshold, 0), 1)
        return 1 - (progress * 0.45)
    }

    private var verticalDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard isZoomed == false else { return }
                let vertical = value.translation.height
                let horizontal = value.translation.width
                guard vertical > 0, abs(vertical) > abs(horizontal) else { return }
                verticalDragOffset = min(vertical, 360)
            }
            .onEnded { value in
                guard isZoomed == false else {
                    resetVerticalDragOffset()
                    return
                }
                let vertical = value.translation.height
                let horizontal = value.translation.width

                guard vertical > 0, abs(vertical) > abs(horizontal) else {
                    resetVerticalDragOffset()
                    return
                }

                if vertical >= dismissDragThreshold {
                    onDismiss()
                } else {
                    resetVerticalDragOffset()
                }
            }
    }

    private func resetVerticalDragOffset() {
        guard verticalDragOffset != 0 else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            verticalDragOffset = 0
        }
    }
}
