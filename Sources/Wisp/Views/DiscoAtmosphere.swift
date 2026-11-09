import SwiftUI

/// Audio-driven light lives only inside a player surface. Playback controls,
/// titles, and the library never inherit its changing colors or animation.
struct DiscoAtmosphere: View {
    enum Presentation { case compact, expanded }
    var presentation: Presentation = .compact
    @Environment(\.colorScheme) private var scheme
    @State private var envelope = AuraMotionEnvelope()
    @State private var motion = AuraMotion.zero
    private var theme: WispTheme { .shared }

    private func response(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return sqrt(min(1, max(0, value) * 5))
    }

    private func color(_ value: AuraRGB) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }

    private var primaryColor: Color {
        color(scheme == .dark ? theme.auraColors.darkPrimary : theme.auraColors.lightPrimary)
    }
    private var secondaryColor: Color {
        color(scheme == .dark ? theme.auraColors.darkSecondary : theme.auraColors.lightSecondary)
    }

    var body: some View {
        Group {
            if presentation == .expanded { expanded }
            else { compact }
        }
        .onChange(of: theme.lightFrame, initial: true) { _, frame in
            guard presentation == .expanded else { return }
            motion = envelope.consume(frame, at: ProcessInfo.processInfo.systemUptime,
                                      enabled: !theme.reduceMotion)
        }
        .animation(theme.reduceMotion ? nil : .linear(duration: 0.14), value: theme.auraColors)
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }

    /// The compact 17-point player strip deliberately keeps its earlier response.
    private var compact: some View {
        let frame = theme.lightFrame
        let bass = response(frame.bass), mid = response(frame.mid), treble = response(frame.treble)
        let energy = response(frame.energy)
        let spread = min(1, max(0, frame.stereoSpread))
        let balance = (frame.right - frame.left) / max(0.001, frame.right + frame.left)
        let phase = balance * 1.2 + mid * 0.7 - treble * 0.35
        let primary = primaryColor, secondary = secondaryColor
        let lineOpacity = scheme == .dark ? 0.42 : 0.30
        return ZStack {
            LinearGradient(colors: [.clear, primary, secondary, .clear], startPoint: .leading, endPoint: .trailing)
                .opacity(energy * (scheme == .dark ? 0.045 : 0.025))
                .blur(radius: 7)
            PlayerLightRibbon(amplitude: bass * 0.65 + mid * 0.35, detail: treble * 0.12,
                              phase: phase, spread: spread)
                .stroke(line(primary), lineWidth: 0.7)
                .opacity(energy * lineOpacity)
            PlayerLightRibbon(amplitude: mid * 0.45 + treble * 0.2, detail: bass * 0.08,
                              phase: phase + 1.8, spread: spread * 0.75)
                .stroke(line(secondary), lineWidth: 0.55)
                .opacity(energy * lineOpacity * 0.48)
        }
        .animation(theme.reduceMotion ? nil : .easeOut(duration: 0.24), value: frame)
    }

    private var expanded: some View {
        let primary = primaryColor, secondary = secondaryColor
        let visibility = min(1, motion.energy * 1.7)
        let height = min(0.96, 0.055 + motion.energy * 0.48 + motion.sustained * 0.30
                         + motion.bass * 0.23 + motion.impact * 0.2)
        let width = min(1, 0.70 + motion.sustained * 0.23 + motion.spread * 0.07)
        let main = AuraContour(amplitude: height, mid: motion.mid, treble: motion.treble,
                               phase: motion.phase, width: width, spread: motion.spread,
                               balance: motion.balance, impact: motion.impact)
        let middle = AuraContour(amplitude: height * (0.62 + motion.mid * 0.15), mid: motion.treble,
                                 treble: motion.mid, phase: motion.phase * 0.82 + 2.1,
                                 width: min(1, width + 0.06), spread: motion.spread * 0.75,
                                 balance: -motion.balance * 0.6, impact: motion.impact * 0.45)
        let fine = AuraContour(amplitude: height * (0.42 + motion.treble * 0.18), mid: motion.mid,
                               treble: motion.treble, phase: motion.phase * 0.67 + 4.2,
                               width: min(1, width + 0.1), spread: motion.spread * 0.5,
                               balance: motion.balance * 0.4, impact: motion.impact * 0.25)
        return ZStack {
            GeometryReader { geometry in
                let reach = max(geometry.size.width, geometry.size.height)
                RadialGradient(colors: [primary, .clear],
                               center: UnitPoint(x: 0.46 + motion.balance * 0.04, y: 0.48),
                               startRadius: 0, endRadius: reach * (0.28 + motion.sustained * 0.16))
                    .opacity(visibility * (scheme == .dark ? 0.12 : 0.065))
                RadialGradient(colors: [secondary, .clear],
                               center: UnitPoint(x: 0.56 - motion.balance * 0.03, y: 0.55),
                               startRadius: 0, endRadius: reach * (0.22 + motion.mid * 0.12))
                    .opacity(visibility * (scheme == .dark ? 0.055 : 0.025))
            }
            main.stroke(line(primary), lineWidth: 5.5)
                .blur(radius: 5).opacity(visibility * (scheme == .dark ? 0.16 : 0.05))
            main.stroke(line(primary, secondary), lineWidth: 1.15)
                .opacity(visibility * (scheme == .dark ? 0.90 : 0.72))
            middle.stroke(line(secondary, primary), lineWidth: 0.85)
                .opacity(visibility * (scheme == .dark ? 0.60 : 0.49))
            fine.stroke(line(primary), lineWidth: 0.65)
                .opacity(visibility * (scheme == .dark ? 0.34 : 0.30))
        }
        .animation(theme.reduceMotion || theme.lightFrame == .zero ? nil : .linear(duration: 0.12), value: motion)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .white, location: 0.15),
                                   .init(color: .white, location: 0.85),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func line(_ color: Color, _ other: Color? = nil) -> LinearGradient {
        LinearGradient(stops: [.init(color: .clear, location: 0),
                               .init(color: color, location: 0.25),
                               .init(color: other ?? color, location: 0.75),
                               .init(color: .clear, location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// The expanded contours combine bass-scale movement with smaller mid/treble
/// texture. This is a musical-energy visualization, not a literal PCM waveform.
private struct AuraContour: Shape {
    var amplitude: Double
    var mid: Double
    var treble: Double
    var phase: Double
    var width: Double
    var spread: Double
    var balance: Double
    var impact: Double
    typealias Pair = AnimatablePair<Double, Double>
    typealias Quad = AnimatablePair<Pair, Pair>
    var animatableData: AnimatablePair<Quad, Quad> {
        get { .init(.init(.init(amplitude, mid), .init(treble, phase)),
                    .init(.init(width, spread), .init(balance, impact))) }
        set {
            amplitude = newValue.first.first.first; mid = newValue.first.first.second
            treble = newValue.first.second.first; phase = newValue.first.second.second
            width = newValue.second.first.first; spread = newValue.second.first.second
            balance = newValue.second.second.first; impact = newValue.second.second.second
        }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0...180 {
            let t = Double(index) / 180
            let envelope = pow(max(0, sin(t * .pi)), 0.85)
            let broad = sin(t * .pi * (2.4 + spread * 0.9) + phase + balance * 0.5)
            let body = sin(t * .pi * (5.2 + mid * 3.6) - phase * 0.65) * mid * 0.25
            let detail = sin(t * .pi * (14 + treble * 18) + phase * 0.35) * treble * 0.08
            let attack = sin(t * .pi * 4 - phase * 1.2) * impact * 0.12
            let wave = (broad * 0.74 + body + detail + attack) / (1 + impact * 0.12)
            let point = CGPoint(x: rect.midX + (t - 0.5) * rect.width * width,
                                y: rect.midY + wave * rect.height * 0.44 * amplitude * envelope)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The restrained compact strip preserves its existing two-contour geometry.
private struct PlayerLightRibbon: Shape {
    var amplitude: Double
    var detail: Double
    var phase: Double
    var spread: Double
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { .init(.init(amplitude, detail), .init(phase, spread)) }
        set {
            amplitude = newValue.first.first; detail = newValue.first.second
            phase = newValue.second.first; spread = newValue.second.second
        }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0...100 {
            let t = Double(index) / 100
            let envelope = pow(sin(t * .pi), 2)
            let wave = sin(t * .pi * (3.5 + spread) + phase) + sin(t * .pi * 7 - phase) * detail
            let point = CGPoint(x: rect.width * t,
                                y: rect.midY + wave * rect.height * 0.30 * amplitude * envelope)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
