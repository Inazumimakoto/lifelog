import SwiftUI

/// Tag colors remain separate; marker size alone communicates repeat visits.
struct ReviewMapMarker: View, Equatable {
    let colors: [Color]
    let diameter: CGFloat
    let isSelected: Bool

    var body: some View {
        ZStack {
            if colors.count <= 1 {
                Circle().fill(colors.first ?? .gray)
            } else {
                ForEach(colors.indices, id: \.self) { index in
                    ReviewMapColorSector(index: index, count: colors.count)
                        .fill(colors[index])
                    ReviewMapColorSector(index: index, count: colors.count)
                        .stroke(.white.opacity(0.9), lineWidth: 0.5)
                }
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 1))
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
}

private struct ReviewMapColorSector: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center,
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90 + Double(index) * 360 / Double(count)),
                    endAngle: .degrees(-90 + Double(index + 1) * 360 / Double(count)),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}
