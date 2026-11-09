import SwiftUI
import WispCore

/// One listening shape, continuously blended. Only Shuffle commits a queue.
struct PhoneSmartShuffleView: View {
    let tracks: [Track]
    let title: String
    @EnvironmentObject private var library: PhoneLibraryStore
    @EnvironmentObject private var player: PhonePlayerStore

    var body: some View {
        PhoneSmartShuffleControl(tracks: tracks, title: title, library: library,
                                 player: player, analysis: player.energyAnalysis)
    }
}

private struct PhoneSmartShuffleControl: View {
    let tracks: [Track]
    let title: String
    @ObservedObject var library: PhoneLibraryStore
    @ObservedObject var player: PhonePlayerStore
    @ObservedObject var analysis: PhoneSongEnergyAnalysis
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var position = 1.0
    @State private var pending: EnergyCurve?
    @State private var request: Task<Void, Never>?
    @State private var error: String?

    private var curve: EnergyCurve { .listeningBlend(at: position) }
    private var busy: Bool { pending != nil || analysis.isAnalyzing }
    private var color: Color { blendColor(at: position) }
    private var blendValue: String {
        let value = EnergyCurve.clampListeningBlendPosition(position)
        if value < 0.005 { return "Focus" }
        if abs(value - 1) < 0.005 { return "Flow" }
        if value > 1.995 { return "Surge" }
        let percent = Int(((value < 1 ? value : value - 1) * 100).rounded())
        return value < 1 ? "Focus to Flow, \(percent) percent" : "Flow to Surge, \(percent) percent"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title).font(.wispText(.caption)).foregroundStyle(.secondary)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || pending != nil)) { timeline in
                        let phase = reduceMotion ? 0.45 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 9) / 9
                        PhoneEnergyWave(curve: pending ?? curve, color: color, phase: phase, reduceMotion: reduceMotion)
                    }
                    .frame(height: typeSize.isAccessibilitySize ? 110 : 154)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Listening energy preview")
                    .accessibilityValue(blendValue)
                    VStack(spacing: 6) {
                        Slider(value: $position, in: 0...2).tint(color)
                            .accessibilityLabel("Listening shape")
                            .accessibilityValue(blendValue)
                            .accessibilityHint("Blend from Focus through Flow to Surge. Choose Shuffle to start.")
                        HStack {
                            stop("Focus", at: 0)
                            Spacer(minLength: 5)
                            stop("Flow", at: 1)
                            Spacer(minLength: 5)
                            stop("Surge", at: 2)
                        }
                    }.disabled(busy)
                    if let error {
                        Text(error).font(.wispText(.caption)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if pending != nil {
                        VStack(spacing: 10) {
                            ProgressView(value: Double(analysis.completed), total: Double(max(1, analysis.total))).tint(color)
                            HStack {
                                Text("Preparing \(analysis.completed) of \(analysis.total)…")
                                    .font(.wispText(.caption)).foregroundStyle(.secondary)
                                Spacer()
                                Button("Cancel", action: cancelRequest).font(.wispText(.caption))
                                    .frame(minHeight: 44)
                            }
                        }
                    } else {
                        Button(action: start) {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.wispText(.body, medium: true))
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent).tint(color)
                        .foregroundStyle(scheme == .dark ? PhoneStyle.background : .white)
                        .disabled(busy || tracks.isEmpty || library.snapshot == nil)
                        .accessibilityLabel("Start Smart Shuffle")
                        .accessibilityHint("Plays up to twenty songs matching this energy shape.")
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 18)
                .frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
            .background(PhoneStyle.background)
            .navigationTitle("Smart Shuffle").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { cancelRequest(); dismiss() } label: { Image(systemName: "xmark") }
                        .foregroundStyle(PhoneStyle.muted)
                        .accessibilityLabel("Close Smart Shuffle")
                }
            }
        }
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
        .onAppear { position = player.energyCurve.nearestListeningBlendPosition }
        .onDisappear(perform: cancelRequest)
    }

    private func stop(_ label: String, at stop: Double) -> some View {
        let selected = abs(position - stop) < 0.005
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { position = stop }
        } label: {
            Text(label).font(.wispText(.caption, medium: selected))
                .foregroundStyle(selected ? blendColor(at: stop) : .secondary)
                .frame(minWidth: 48, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set listening shape to \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func blendColor(at position: Double) -> Color {
        let stops: [UInt32] = scheme == .dark ? [0xD1A13A, 0x4EACFF, 0xFF6677] : [0x815E0A, 0x17639B, 0xA72E42]
        let value = EnergyCurve.clampListeningBlendPosition(position), index = min(1, Int(value))
        let fraction = value - Double(index), eased = fraction * fraction * (3 - 2 * fraction)
        func channel(_ shift: UInt32) -> Double {
            let first = Double((stops[index] >> shift) & 0xff), second = Double((stops[index + 1] >> shift) & 0xff)
            return (first + (second - first) * eased) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }

    private func start() {
        guard request == nil, !analysis.isAnalyzing, let snapshot = library.snapshot else { return }
        // Resolve the presented collection once, against one immutable snapshot.
        // A removed song is omitted; unrelated songs can never enter this request.
        let byID = Dictionary(uniqueKeysWithValues: snapshot.document.tracks.map { ($0.id, $0) })
        let selected = tracks.compactMap { byID[$0.id] }
        let selectedCurve = curve
        pending = selectedCurve; error = nil
        request = Task { @MainActor in
            let started = await player.startSmartShuffle(tracks: selected, snapshot: snapshot, curve: selectedCurve)
            let cancelled = Task.isCancelled
            request = nil; pending = nil
            if started { dismiss() }
            else if !cancelled { error = player.errorMessage ?? "Couldn’t start this shuffle. Please try again." }
        }
    }

    private func cancelRequest() {
        guard request != nil else { return }
        request?.cancel(); player.cancelSmartShuffle()
    }
}

private struct PhoneEnergyWave: View {
    let curve: EnergyCurve
    let color: Color
    let phase: Double
    let reduceMotion: Bool

    var body: some View {
        let line = PhoneListeningEnergyLine(curve: curve)
        ZStack {
            PhoneListeningEnergyLine(curve: curve, filled: true)
                .fill(LinearGradient(colors: [color.opacity(0.14), color.opacity(0.005)], startPoint: .top, endPoint: .bottom))
            line.stroke(color.opacity(0.08), style: StrokeStyle(lineWidth: 5, lineCap: .round)).blur(radius: 3)
            line.stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if !reduceMotion {
                line.stroke(LinearGradient(stops: [
                    .init(color: .clear, location: max(0, phase - 0.24)),
                    .init(color: color, location: phase),
                    .init(color: .clear, location: min(1, phase + 0.24))
                ], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
            }
        }.drawingGroup()
    }
}

private struct PhoneListeningEnergyLine: Shape {
    var first: Double; var second: Double; var third: Double; var fourth: Double; var fifth: Double
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
                let point = CGPoint(x: rect.minX + rect.width * x, y: rect.minY + 8 + max(1, rect.height - 16) * (1 - curve.value(at: x)))
                if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            if filled {
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.closeSubpath()
            }
        }
    }
}
