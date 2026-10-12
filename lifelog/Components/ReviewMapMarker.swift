import SwiftUI

/// Tag colors remain separate; marker size alone communicates repeat visits.
struct ReviewMapMarker: View, Equatable {
    let colors: [Color]
    let diameter: CGFloat
    let isSelected: Bool

    var body: some View {
        Group {
            if colors.count <= 1 {
                // The overview has many single-color points; retain the native shape path.
                Circle()
                    .fill(colors.first ?? .gray)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 0.5))
            } else {
                segmentedCircle
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
        .overlay {
            if isSelected {
                Circle()
                    .stroke(Color.primary, lineWidth: 1.5)
                    .padding(-3)
            }
        }
    }

    private var segmentedCircle: some View {
        // Draw tag segments together so each map point keeps a small, stable view tree.
        Canvas(rendersAsynchronously: false) { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let circle = Path(ellipseIn: bounds)
            context.clip(to: circle)

            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = min(size.width, size.height) / 2
            var separators = Path()
            for index in colors.indices {
                let startAngle = Angle.degrees(-90 + Double(index) * 360 / Double(colors.count))
                let endAngle = Angle.degrees(-90 + Double(index + 1) * 360 / Double(colors.count))
                var sector = Path()
                sector.move(to: center)
                sector.addArc(center: center, radius: radius,
                              startAngle: startAngle, endAngle: endAngle, clockwise: false)
                sector.closeSubpath()
                context.fill(sector, with: .color(colors[index]))

                let cosine: Double = cos(startAngle.radians)
                let sine: Double = sin(startAngle.radians)
                separators.move(to: center)
                separators.addLine(to: CGPoint(x: center.x + radius * CGFloat(cosine),
                                               y: center.y + radius * CGFloat(sine)))
            }
            context.stroke(separators, with: .color(.white.opacity(0.9)), lineWidth: 0.25)

            context.stroke(Path(ellipseIn: bounds.insetBy(dx: 0.25, dy: 0.25)),
                           with: .color(.white), lineWidth: 0.5)
        }
    }
}
