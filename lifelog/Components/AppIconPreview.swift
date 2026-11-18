import SwiftUI

struct AppIconPreview: View {
    let palette: AppIconPalette

    var body: some View {
        GeometryReader { geometry in
            let cornerRadius = min(geometry.size.width, geometry.size.height) * 0.22
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            Group {
                if palette.alternateName == nil {
                    Image("AppIconPrimaryPreview")
                        .resizable()
                        .environment(\.colorScheme, palette == .primaryDark ? .dark : .light)
                } else {
                    Canvas { context, size in
                        context.withCGContext { AppIconArtwork.draw(palette, in: $0, size: size) }
                    }
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
