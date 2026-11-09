import SwiftUI
import WispCore

@MainActor
struct EnergyCurvePopover: View {
    @ObservedObject var player: PlayerStore
    @ObservedObject var analysis: SongEnergyAnalysis
    let trackIDs: [UUID]
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var position: Double
    @State private var pending: EnergyCurve?
    @State private var request: Task<Void, Never>?
    @State private var error: String?
    private let reduceMotionOverride: Bool?

    init(player: PlayerStore, trackIDs: [UUID], reduceMotion: Bool? = nil, close: @escaping () -> Void) {
        self.player = player
        self.analysis = player.energyAnalysis
        self.trackIDs = trackIDs
        self.close = close
        self.reduceMotionOverride = reduceMotion
        _position = State(initialValue: player.energyCurve.nearestListeningBlendPosition)
    }

    private var curve: EnergyCurve { .listeningBlend(at: position) }
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var color: Color { blendColor(at: position) }
    private var busy: Bool { pending != nil || analysis.isAnalyzing }
    private var blendValue: String {
        let value = EnergyCurve.clampListeningBlendPosition(position)
        if abs(value) < 0.005 { return "Focus" }
        if abs(value - 1) < 0.005 { return "Flow" }
        if abs(value - 2) < 0.005 { return "Surge" }
        let percentage = Int(((value < 1 ? value : value - 1) * 100).rounded())
        return value < 1 ? "Focus to Flow, \(percentage) percent" : "Flow to Surge, \(percentage) percent"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 15) {
                Text("Smart Shuffle").font(WispType.ui(12, weight: .medium))
                Spacer()
                Button(action: start) {
                    Label("Shuffle", systemImage: "shuffle").font(WispType.ui(11))
                }
                .buttonStyle(.plain).foregroundStyle(color)
                .disabled(busy || trackIDs.isEmpty)
                .accessibilityLabel("Start Smart Shuffle")
                .accessibilityHint("Starts the listening shape shown below.")
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10)).frame(width: 18, height: 22)
                }
                .buttonStyle(.plain).foregroundStyle(WispSurface.mutedText)
                .accessibilityLabel("Close Smart Shuffle")
            }
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || pending != nil)) { timeline in
                let phase = reduceMotion ? 0.45 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 9) / 9
                EnergyBlendWave(curve: pending ?? curve, color: color, phase: phase, reduceMotion: reduceMotion)
            }
            .frame(height: 112).padding(.horizontal, 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Listening energy preview")
            .accessibilityValue(blendValue)

            VStack(spacing: 3) {
                Slider(value: $position, in: 0...2)
                    .tint(color)
                    .accessibilityLabel("Listening shape")
                    .accessibilityValue(blendValue)
                    .accessibilityHint("Blend from Focus through Flow to Surge. Shuffle starts the selected shape.")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: position = min(2, position + 0.05)
                        case .decrement: position = max(0, position - 0.05)
                        @unknown default: break
                        }
                    }
                HStack {
                    stopLabel("Focus", at: 0)
                    Spacer()
                    stopLabel("Flow", at: 1)
                    Spacer()
                    stopLabel("Surge", at: 2)
                }
            }
            .disabled(busy)
            if let error {
                Text(error).font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pending != nil {
                VStack(spacing: 8) {
                    ProgressView(value: Double(analysis.completed), total: Double(max(1, analysis.total))).tint(color)
                    HStack {
                        Text("Preparing shuffle…").foregroundStyle(WispSurface.mutedText)
                        Spacer()
                        Button("Cancel", action: cancelRequest).buttonStyle(.plain)
                    }.font(WispType.ui(10))
                }
            }
        }
        .padding(20).frame(width: 380)
        .font(WispType.ui(12)).foregroundStyle(WispSurface.ink).background(WispSurface.main)
        .onDisappear(perform: cancelRequest)
    }

    private func stopLabel(_ title: String, at stop: Double) -> some View {
        let selected = abs(position - stop) < 0.005
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { position = stop }
        } label: {
            Text(title).font(WispType.ui(10, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? blendColor(at: stop) : WispSurface.mutedText)
                .padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Set listening shape to \(title)")
        .accessibilityHint("Previews this shape. Choose Shuffle to start.")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func blendColor(at position: Double) -> Color {
        let stops: [UInt32] = colorScheme == .dark ? [0xD1A13A, 0x4EACFF, 0xFF6677] : [0x815E0A, 0x17639B, 0xA72E42]
        let value = EnergyCurve.clampListeningBlendPosition(position)
        let index = min(1, Int(value))
        let fraction = value - Double(index)
        let eased = fraction * fraction * (3 - 2 * fraction)
        func component(_ shift: UInt32) -> Double {
            let first = Double((stops[index] >> shift) & 0xff)
            let second = Double((stops[index + 1] >> shift) & 0xff)
            return (first + (second - first) * eased) / 255
        }
        return Color(red: component(16), green: component(8), blue: component(0))
    }

    private func start() {
        guard pending == nil, !analysis.isAnalyzing, !trackIDs.isEmpty else { return }
        // Capture the preview once. Changing a draft never mutates the live queue.
        let selectedCurve = curve
        error = nil
        pending = selectedCurve
        request = Task { @MainActor in
            let started = await player.startSmartShuffle(ids: trackIDs, curve: selectedCurve)
            let cancelled = Task.isCancelled
            request = nil
            pending = nil
            if started { close() }
            else if !cancelled { error = player.errorMessage ?? "Couldn’t start this shuffle. Please try again." }
        }
    }

    private func cancelRequest() {
        guard request != nil else { return }
        request?.cancel()
        player.cancelSmartShuffle()
    }
}

/// Motion follows the selected line rather than changing its energy values.
struct EnergyBlendWave: View {
    let curve: EnergyCurve
    let color: Color
    let phase: Double
    let reduceMotion: Bool

    var body: some View {
        let line = ListeningEnergyLine(curve: curve)
        ZStack {
            ListeningEnergyLine(curve: curve, filled: true)
                .fill(LinearGradient(colors: [color.opacity(0.12), color.opacity(0.015)], startPoint: .top, endPoint: .bottom))
            line.stroke(color.opacity(0.15), style: StrokeStyle(lineWidth: 5, lineCap: .round)).blur(radius: 4)
            line.stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            if !reduceMotion {
                line.stroke(LinearGradient(stops: [
                    .init(color: .clear, location: max(0, phase - 0.24)),
                    .init(color: color.opacity(0.75), location: phase),
                    .init(color: .clear, location: min(1, phase + 0.24))
                ], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .drawingGroup()
    }
}

private struct ListeningEnergyLine: Shape {
    var first: Double
    var second: Double
    var third: Double
    var fourth: Double
    var fifth: Double
    var filled: Bool

    init(curve: EnergyCurve, filled: Bool = false) {
        first = curve.levels[0]; second = curve.levels[1]; third = curve.levels[2]
        fourth = curve.levels[3]; fifth = curve.levels[4]; self.filled = filled
    }

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get { AnimatablePair(AnimatablePair(first, second), AnimatablePair(third, AnimatablePair(fourth, fifth))) }
        set {
            first = newValue.first.first; second = newValue.first.second; third = newValue.second.first
            fourth = newValue.second.second.first; fifth = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let curve = EnergyCurve(levels: [first, second, third, fourth, fifth])
        return Path { path in
            for sample in 0...120 {
                let x = Double(sample) / 120
                let point = CGPoint(x: rect.minX + rect.width * x, y: rect.minY + 7 + max(1, rect.height - 14) * (1 - curve.value(at: x)))
                if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            if filled {
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
