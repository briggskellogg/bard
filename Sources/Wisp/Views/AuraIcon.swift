import SwiftUI

/// A small, static resonance mark. Color comes from the surrounding control,
/// never from the audio visualization.
struct AuraIcon: View {
    var size: CGFloat = 14

    var body: some View {
        AuraMark()
            .stroke(style: StrokeStyle(lineWidth: 0.85, lineCap: .round))
            .frame(width: min(14, max(1, size)), height: min(14, max(1, size)))
            .accessibilityHidden(true)
    }
}

private struct AuraMark: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let core = 3.25 * unit
        path.addEllipse(in: CGRect(x: center.x - core, y: center.y - core,
                                   width: core * 2, height: core * 2))
        let radius = 8.75 * unit
        path.move(to: CGPoint(x: center.x + cos(-62 * .pi / 180) * radius,
                              y: center.y + sin(-62 * .pi / 180) * radius))
        path.addArc(center: center, radius: radius, startAngle: .degrees(-62),
                    endAngle: .degrees(62), clockwise: false)
        path.move(to: CGPoint(x: center.x + cos(118 * .pi / 180) * radius,
                              y: center.y + sin(118 * .pi / 180) * radius))
        path.addArc(center: center, radius: radius, startAngle: .degrees(118),
                    endAngle: .degrees(242), clockwise: false)
        return path
    }
}
