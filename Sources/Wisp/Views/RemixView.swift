import SwiftUI
import AppKit
import WispCore

struct RemixAlphaBadge: View {
    var body: some View {
        Text("ALPHA")
            .font(WispType.ui(9, weight: .medium)).tracking(0.6)
            .foregroundStyle(WispSurface.amber)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(WispSurface.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
            .fixedSize().accessibilityLabel("Alpha")
    }
}

/// One performance surface: source, tone, live instrument, and a durable mixed take.
@MainActor
struct RemixView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var engine: RemixStore
    @State private var childTitle: String
    @State private var artistCredit: String
    @State private var asVersion = false
    @State private var saving = false
    @State private var closing = false
    @State private var localError: String?
    @State private var discardPresented = false
    @State private var point = CGPoint(x: 0.5, y: 0.5)
    @State private var trail: [CGPoint] = []
    @State private var trailOpacity = 0.0
    @FocusState private var padFocused: Bool

    private let viewport: CGSize
    let track: Track
    let takesDirectory: URL
    let saveChild: (RemixRecordedTake, String, String) async -> Bool
    let saveVersion: (RemixRecordedTake) async -> Bool

    private let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    init(track: Track, sourceURL: URL, takesDirectory: URL,
         saveChild: @escaping (RemixRecordedTake, String, String) async -> Bool,
         saveVersion: @escaping (RemixRecordedTake) async -> Bool,
         engine: RemixStore? = nil, viewport: CGSize? = nil, initiallySaveAsVersion: Bool = false) {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 900)
        self.viewport = viewport ?? CGSize(width: min(940, max(680, screen.width - 100)), height: min(740, max(440, screen.height - 120)))
        self.track = track
        self.takesDirectory = takesDirectory
        self.saveChild = saveChild
        self.saveVersion = saveVersion
        _engine = StateObject(wrappedValue: engine ?? RemixStore(sourceURL: sourceURL, title: track.displayTitle, takesDirectory: takesDirectory))
        _asVersion = State(initialValue: initiallySaveAsVersion)
        _childTitle = State(initialValue: "\(track.displayTitle) — Remix")
        _artistCredit = State(initialValue: track.artist)
    }

    private var busy: Bool { saving || closing || engine.isFinalizing }
    private var padColor: Color {
        switch engine.voice {
        case .air, .sub, .drift: return WispSurface.cyan
        case .pulse, .pluck: return WispSurface.amber
        case .glass, .arc, .haze: return WispSurface.magenta
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            sourceTransport
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    voices
                    pad
                    instrumentControls
                }
                VStack(alignment: .leading, spacing: 18) {
                    equalizer
                    levelControls
                }
                .frame(width: 220)
            }
            sourceLoop
            WispSurface.divider.frame(height: 1)
            captureControls
            if let error = localError ?? library.errorMessage ?? engine.errorMessage {
                Text(error).font(WispType.ui(11)).foregroundStyle(WispSurface.amber)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(3)
            }
            }
            .padding(.bottom, 4)
            }
            .scrollIndicators(.automatic)
        }
        .padding(24).frame(width: viewport.width, height: viewport.height)
        .background(WispSurface.main).foregroundStyle(WispSurface.ink).tint(WispSurface.cyan)
        .interactiveDismissDisabled()
        .task {
            WispInput.remix = engine
            await engine.prepare()
        }
        .onDisappear {
            engine.releaseTouch()
            engine.shutdown()
            if WispInput.remix === engine { WispInput.remix = nil }
        }
        .onChange(of: padFocused) { _, focused in if !focused { engine.releaseTouch() } }
        .onChange(of: engine.isTouching) { _, touching in if !touching { fadeTrail() } }
        .onChange(of: reduceMotion) { _, reduced in if reduced { trail.removeAll(); trailOpacity = 0 } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in engine.releaseTouch() }
        .confirmationDialog("Discard this recording?", isPresented: $discardPresented, titleVisibility: .visible) {
            Button("Discard recording", role: .destructive) { engine.discardTake() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the unsaved capture. Songs already saved to your library are unchanged.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Remix").font(WispType.ui(18, weight: .medium))
                    RemixAlphaBadge()
                }
                .accessibilityElement(children: .combine)
                Text(track.displayTitle).font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if engine.isPreparing { ProgressView().controlSize(.small) }
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11)).frame(width: 24, height: 24)
            }
            .buttonStyle(.plain).foregroundStyle(WispSurface.mutedText)
            .keyboardShortcut(.cancelAction).accessibilityLabel("Close remix station")
            .disabled(busy)
        }
    }

    private var sourceTransport: some View {
        HStack(spacing: 13) {
            Button { engine.playPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15)).frame(width: 26, height: 28)
            }
            .buttonStyle(.plain).accessibilityLabel(engine.isPlaying ? "Pause source" : "Play source")
            .disabled(engine.isPreparing || busy)
            Text(clockText(engine.position)).font(WispType.ui(11)).monospacedDigit().frame(width: 42, alignment: .trailing)
            Slider(value: Binding(get: { engine.position }, set: { engine.seek(to: $0) }), in: 0...max(0.01, engine.duration))
                .controlSize(.small).accessibilityLabel("Source position")
                .disabled(engine.isPreparing || busy)
            Text(clockText(engine.duration)).font(WispType.ui(11)).monospacedDigit()
                .foregroundStyle(WispSurface.mutedText).frame(width: 42, alignment: .leading)
        }
    }

    private var voices: some View {
        HStack(spacing: 8) {
            ForEach(RemixVoice.allCases, id: \.self) { voice in
                Button {
                    engine.releaseTouch()
                    engine.voice = voice
                    padFocused = true
                } label: {
                    VStack(spacing: 6) {
                        Text(voice.title).font(WispType.ui(11))
                            .foregroundStyle(engine.voice == voice ? WispSurface.ink : WispSurface.mutedText)
                        Capsule().fill(engine.voice == voice ? padColor : .clear).frame(height: 1.5)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(voice.detail)
                .accessibilityLabel("\(voice.title) voice")
                .accessibilityAddTraits(engine.voice == voice ? .isSelected : [])
            }
        }
        .disabled(engine.isPreparing || busy)
    }

    private var pad: some View {
        GeometryReader { geometry in
            let x = point.x * geometry.size.width
            let y = point.y * geometry.size.height
            ZStack {
                WispSurface.sidebar
                RadialGradient(colors: [padColor.opacity(engine.isTouching ? 0.19 : 0.06), .clear],
                               center: UnitPoint(x: point.x, y: point.y), startRadius: 0, endRadius: 220)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || (!engine.isPlaying && !engine.isTouching && !engine.isPreviewingTake))) { timeline in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        let level = min(1, max(0, Double(engine.outputLevel)))
                        for line in 0..<3 {
                            var path = Path()
                            for step in 0...100 {
                                let fraction = Double(step) / 100
                                let envelope = pow(sin(.pi * fraction), 1.5)
                                let wave = sin(fraction * .pi * (3 + Double(line)) + time * (0.65 + Double(line) * 0.13))
                                let offset = wave * (8 + level * 38) * envelope
                                let location = CGPoint(x: fraction * size.width,
                                    y: size.height * (0.48 + Double(line) * 0.035) + offset)
                                if step == 0 { path.move(to: location) } else { path.addLine(to: location) }
                            }
                            context.stroke(path, with: .color((line == 1 ? WispSurface.magenta : padColor).opacity(0.08 + level * 0.25)), lineWidth: 0.8)
                        }
                    }
                }
                if !reduceMotion && trail.count > 1 {
                    Path { $0.addLines(trail.map { CGPoint(x: $0.x * geometry.size.width, y: $0.y * geometry.size.height) }) }
                        .stroke(padColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                        .opacity(trailOpacity)
                }
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }.stroke(padColor.opacity(engine.isTouching ? 0.12 : 0.04), lineWidth: 0.5)
                Circle().stroke(padColor.opacity(engine.isTouching ? 0.22 : 0.08), lineWidth: 0.7)
                    .frame(width: 80, height: 80).position(x: x, y: y)
                Circle().fill(engine.isTouching ? padColor : WispSurface.mutedText)
                    .frame(width: engine.isTouching ? 7 : 4, height: engine.isTouching ? 7 : 4)
                    .shadow(color: padColor.opacity(engine.isTouching ? 0.6 : 0), radius: 12)
                    .position(x: x, y: y)
                VStack {
                    HStack { Text("HOLD + GLIDE"); Spacer(); Text("BRIGHTER ↑") }
                    Spacer()
                    HStack { Text("← LOWER"); Spacer(); Text("HIGHER →") }
                }
                .font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText).padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !engine.isPreparing && !busy else { return }
                padFocused = true
                point = CGPoint(x: min(1, max(0, value.location.x / geometry.size.width)),
                                y: min(1, max(0, value.location.y / geometry.size.height)))
                playPoint()
            }.onEnded { _ in engine.releaseTouch() })
            .focusable().focused($padFocused).focusEffectDisabled()
            .onKeyPress(.space, phases: [.down, .up]) { press in
                if press.phase == .up { engine.releaseTouch() }
                else if !engine.isPreparing && !busy { playPoint() }
                return .handled
            }
            .onKeyPress(.leftArrow) { movePoint(x: -0.025, y: 0); return .handled }
            .onKeyPress(.rightArrow) { movePoint(x: 0.025, y: 0); return .handled }
            .onKeyPress(.upArrow) { movePoint(x: 0, y: -0.05); return .handled }
            .onKeyPress(.downArrow) { movePoint(x: 0, y: 0.05); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Theremin touch pad")
            .accessibilityValue(engine.isTouching ? "Playing \(engine.voice.title)" : "Ready")
            .accessibilityHint("Hold and glide, or hold Space and use arrow keys. Left and right change pitch. Up and down change brightness.")
            .accessibilityAdjustableAction { direction in movePoint(x: direction == .increment ? 0.05 : -0.05, y: 0) }
        }
        .frame(height: 220)
    }

    private var instrumentControls: some View {
        HStack(spacing: 17) {
            Menu {
                Toggle("Stay in key", isOn: $engine.quantized)
                Picker("Key", selection: $engine.rootNote) {
                    ForEach(0..<12, id: \.self) { Text("\(noteNames[$0]) minor").tag($0) }
                }.disabled(!engine.quantized)
            } label: {
                HStack(spacing: 5) {
                    Text(engine.quantized ? "\(noteNames[min(11, max(0, engine.rootNote))]) minor" : "Free pitch")
                    Image(systemName: "chevron.down").font(.system(size: 7))
                }
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Theremin pitch and key")
            Toggle("Echo", isOn: $engine.echo).toggleStyle(.checkbox)
            Spacer()
            Text("Space holds · Arrows move").font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
        }
        .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
        .disabled(engine.isPreparing || busy)
    }

    private var equalizer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SOURCE EQ").font(WispType.ui(12, weight: .medium))
                Spacer()
                Button("Reset") { engine.resetEQ() }.buttonStyle(.plain)
                    .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
            }
            RemixEQCurve(gains: $engine.eqGains)
            Text("Drag · Double-click resets")
                .font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
        }
        .disabled(engine.isPreparing || busy)
    }

    private var levelControls: some View {
        VStack(spacing: 12) {
            level("Source", value: $engine.sourceVolume)
            level("Instrument", value: $engine.instrumentVolume)
            level("Monitor", value: $engine.volume)
                .help("Listening volume only. This does not change the saved recording.")
        }
        .disabled(engine.isPreparing || busy)
    }

    private func level(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label).lineLimit(1).frame(width: 74, alignment: .leading)
            Slider(value: value, in: 0...1).controlSize(.mini).accessibilityLabel("\(label) level")
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit().foregroundStyle(WispSurface.mutedText)
                .frame(width: 29, alignment: .trailing)
        }.font(WispType.ui(10))
    }

    private var sourceLoop: some View {
        HStack(spacing: 15) {
            Toggle("Loop source", isOn: $engine.loopEnabled).toggleStyle(.checkbox)
                .accessibilityLabel("Loop the selected source region")
            Button("Set in") { setLoopIn() }.buttonStyle(.plain).foregroundStyle(.tint)
            Text(clockText(engine.loopStart)).monospacedDigit().foregroundStyle(WispSurface.mutedText)
            Button("Set out") { engine.loopEnd = min(engine.duration, engine.loopStart + 60, engine.position) }
                .buttonStyle(.plain).foregroundStyle(.tint)
                .disabled(engine.position <= engine.loopStart + 0.05)
            Text(clockText(engine.loopEnd)).monospacedDigit().foregroundStyle(WispSurface.mutedText)
            Spacer()
            Text("\(clockText(max(0, engine.loopEnd - engine.loopStart))) region · up to 1:00")
                .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
        }
        .font(WispType.ui(11)).disabled(engine.isPreparing || busy)
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Button(action: capture) {
                    Label(engine.isRecording ? "Finish take" : "Record", systemImage: engine.isRecording ? "stop.fill" : "record.circle")
                        .font(WispType.ui(12))
                }
                .buttonStyle(.plain).foregroundStyle(engine.isRecording ? WispSurface.amber : WispSurface.ink)
                .disabled(engine.isPreparing || busy || (!engine.isRecording && engine.recordedTake != nil))
                Text(engine.isRecording ? "\(clockText(engine.recordingDuration)) / 15:00" : "Record track + pad")
                    .font(WispType.ui(10)).monospacedDigit().foregroundStyle(WispSurface.mutedText)
                Spacer()
                if let take = engine.recordedTake {
                    Button { engine.previewTake() } label: {
                        Label(engine.isPreviewingTake ? "Pause take" : "Preview take", systemImage: engine.isPreviewingTake ? "pause.fill" : "play.fill")
                    }.buttonStyle(.plain).disabled(busy || engine.isRecording)
                    Toggle("Repeat take", isOn: $engine.loopTakePreview).toggleStyle(.checkbox)
                        .disabled(busy || engine.isRecording)
                    Text(clockText(take.duration)).monospacedDigit().foregroundStyle(WispSurface.mutedText)
                }
                Menu {
                        ForEach(engine.recoveredTakes) { take in
                            Button("\(take.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(clockText(take.duration))") {
                                engine.selectRecoveredTake(id: take.id)
                            }
                        }
                        Divider()
                        Button("Reveal takes") { revealTakes() }
                        Button("Discard current take…", role: .destructive) { discardPresented = true }
                            .disabled(engine.recordedTake == nil)
                    } label: { Image(systemName: "ellipsis").frame(width: 18, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Saved captures")
                    .disabled(busy || engine.isRecording)
            }
            .font(WispType.ui(10))
            if let take = engine.recordedTake {
                saveControls(take)
            } else {
                Text(engine.isFinalizing ? "Finishing your recording…" : engine.isRecording ? "You can pause the source and keep playing the pad. Closing keeps this take." : "Takes are kept when you close. Save one as a child song or a new version of this song.")
                    .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
            }
        }
    }

    private func saveControls(_ take: RemixRecordedTake) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .bottom, spacing: 16) {
                Picker("Save as", selection: $asVersion) {
                    Text("Child song").tag(false)
                    Text("New version").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220).accessibilityLabel("Save recording as")
                if !asVersion {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title").font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
                        TextField("Remix title", text: $childTitle).modifier(QuietFieldLine()).accessibilityLabel("Child song title")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Artist credit").font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
                        TextField("Artist credit", text: $artistCredit).modifier(QuietFieldLine()).accessibilityLabel("Child song artist credit")
                    }.frame(width: 170)
                } else {
                    Text("The current audio will stay in Previous versions.")
                        .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(saving ? "Saving…" : asVersion ? "Save version" : "Save child") { save(take) }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || engine.isRecording || (!asVersion && childTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .disabled(saving || closing)
            Text(asVersion ? "Same song, playlists, and listening history." : "A separate Classic song, linked to its source. Check the artist credit before saving.")
                .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
        }
    }

    private func playPoint() {
        guard !engine.isPreparing && !busy else { return }
        if !reduceMotion {
            if !engine.isTouching { trail.removeAll() }
            if trail.last.map({ hypot($0.x - point.x, $0.y - point.y) > 0.003 }) ?? true { trail.append(point) }
            if trail.count > 36 { trail.removeFirst(trail.count - 36) }
            trailOpacity = 1
        }
        engine.touch(x: Double(point.x), y: Double(1 - point.y))
    }

    private func movePoint(x: CGFloat, y: CGFloat) {
        point.x = min(1, max(0, point.x + x)); point.y = min(1, max(0, point.y + y))
        if engine.isTouching { playPoint() }
    }

    private func fadeTrail() {
        if reduceMotion { trailOpacity = 0 }
        else { withAnimation(.easeOut(duration: 0.4)) { trailOpacity = 0 } }
    }

    private func setLoopIn() {
        let start = min(max(0, engine.position), max(0, engine.duration - 0.1))
        let end = min(engine.duration, start + 60, max(start + 0.1, engine.loopEnd))
        engine.loopStart = start
        engine.loopEnd = end
    }

    private func revealTakes() {
        let folder = takesDirectory.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch { localError = "Bard couldn’t open the captures folder: \(error.localizedDescription)" }
    }

    private func capture() {
        engine.releaseTouch()
        localError = nil
        if engine.isRecording {
            Task { _ = await engine.finishRecording() }
        } else {
            engine.startRecording()
        }
        padFocused = true
    }

    private func save(_ take: RemixRecordedTake) {
        saving = true
        localError = nil
        library.errorMessage = nil
        engine.releaseTouch()
        engine.stopTakePreview()
        if engine.isPlaying { engine.playPause() }
        Task { @MainActor in
            let succeeded = asVersion ? await saveVersion(take) : await saveChild(take, childTitle, artistCredit)
            saving = false
            if succeeded {
                engine.discardTake(id: take.id)
                close()
            } else if library.errorMessage == nil {
                localError = "The recording could not be saved. It is still available in Saved captures."
            }
        }
    }

    private func close() {
        guard !busy else { return }
        closing = true
        engine.releaseTouch()
        Task { @MainActor in
            if engine.isRecording { _ = await engine.finishRecording() }
            engine.shutdown()
            if WispInput.remix === engine { WispInput.remix = nil }
            dismiss()
        }
    }
}

private struct RemixEQCurve: View {
    @Binding var gains: [Double]
    private let labels = ["80", "250", "1k", "4k", "12k"]

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let values = (0..<5).map { index in min(12, max(-12, gains.indices.contains(index) ? gains[index] : 0)) }
                let points = values.enumerated().map { index, gain in
                    CGPoint(x: width * (Double(index) + 0.5) / 5, y: height * (0.5 - gain / 24))
                }
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height / 2)); path.addLine(to: CGPoint(x: width, y: height / 2))
                        for point in points {
                            path.move(to: CGPoint(x: point.x, y: 0)); path.addLine(to: CGPoint(x: point.x, y: height))
                        }
                    }.stroke(WispSurface.divider.opacity(0.65), lineWidth: 0.5)
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: CGPoint(x: 0, y: first.y))
                        path.addLine(to: first)
                        for index in 1..<points.count {
                            let previous = points[index - 1], point = points[index]
                            let middle = (previous.x + point.x) / 2
                            path.addCurve(to: point, control1: CGPoint(x: middle, y: previous.y), control2: CGPoint(x: middle, y: point.y))
                        }
                        if let last = points.last { path.addLine(to: CGPoint(x: width, y: last.y)) }
                    }.stroke(WispSurface.cyan, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    ForEach(0..<5, id: \.self) { index in
                        Circle().fill(WispSurface.cyan).frame(width: 6, height: 6).position(points[index])
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { index in
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                    set(index, 12 - Double(value.location.y / max(1, height)) * 24)
                                })
                                .simultaneousGesture(TapGesture(count: 2).onEnded { set(index, 0) })
                                .accessibilityElement()
                                .accessibilityLabel("\(labels[index]) hertz equalizer band")
                                .accessibilityValue("\(Int(values[index].rounded())) decibels")
                                .accessibilityAdjustableAction { direction in set(index, values[index] + (direction == .increment ? 1 : -1)) }
                                .help("\(labels[index]) Hz · Drag for gain, double-click to reset")
                        }
                    }
                }
            }
            .frame(height: 122)
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    VStack(spacing: 5) {
                        Text(labels[index]).foregroundStyle(WispSurface.mutedText)
                        Text(String(format: "%+.0f", gains.indices.contains(index) ? gains[index] : 0)).monospacedDigit()
                    }.font(WispType.ui(9)).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func set(_ index: Int, _ gain: Double) {
        guard gains.indices.contains(index) else { return }
        gains[index] = min(12, max(-12, gain))
    }
}
