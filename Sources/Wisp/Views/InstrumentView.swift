import SwiftUI
import AppKit

@MainActor
struct InstrumentView: View {
    @StateObject private var instrument: InstrumentStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var point = CGPoint(x: 0.5, y: 0.5)
    @State private var trail: [CGPoint] = []
    @State private var trailOpacity = 0.0
    @State private var replaceUnsaved = false
    @State private var pendingPhraseID: UUID?
    @FocusState private var fieldFocused: Bool

    private let notes = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    init(instrument: InstrumentStore? = nil) {
        _instrument = StateObject(wrappedValue: instrument ?? InstrumentStore.shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            soundPicker
            field
            parameters
            phraseControls
            if let error = instrument.errorMessage {
                Text(error).font(WispType.ui(12)).foregroundStyle(WispSurface.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20).frame(width: 480)
        .background(WispSurface.main)
        .foregroundStyle(WispSurface.ink)
        .tint(WispSurface.cyan)
        .onAppear { WispInput.instrumentPresented = true; fieldFocused = true }
        .onDisappear { WispInput.instrumentPresented = false; instrument.stop() }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { instrument.release() }
        }
        .onChange(of: instrument.active) { _, active in
            if !active { fadeTrail() }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { trail.removeAll(); trailOpacity = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in instrument.release() }
        .confirmationDialog("Replace the unsaved phrase?", isPresented: $replaceUnsaved, titleVisibility: .visible) {
            Button(pendingPhraseID == nil ? "Record new phrase" : "Open saved phrase", role: .destructive) {
                if let id = pendingPhraseID { instrument.loadPhrase(id: id); pendingPhraseID = nil }
                else { beginRecording() }
            }
            Button("Cancel", role: .cancel) { pendingPhraseID = nil }
        } message: {
            Text("Save the current phrase first if you want to keep it.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Theremin").font(WispType.ui(15, weight: .medium))
            Spacer()
            Text(instrument.active ? instrument.noteName : "HOLD + GLIDE")
                .font(WispType.readout(13)).tracking(0.5)
                .foregroundStyle(WispSurface.mutedText)
                .monospacedDigit()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 10)).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain).foregroundStyle(WispSurface.mutedText)
            .accessibilityLabel("Close instrument")
        }
    }

    private var soundPicker: some View {
        HStack(spacing: 22) {
            ForEach(SoundKind.allCases) { kind in
                Button {
                    instrument.sound = kind
                    fieldFocused = true
                } label: {
                    VStack(spacing: 6) {
                        Text(kind.title).font(WispType.ui(13))
                            .foregroundStyle(instrument.sound == kind ? WispSurface.ink : WispSurface.mutedText)
                        Capsule().fill(instrument.sound == kind ? padColor : .clear).frame(height: 1.5)
                    }
                    .frame(width: 44).padding(.top, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title) sound")
                .accessibilityAddTraits(instrument.sound == kind ? .isSelected : [])
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Instrument sounds")
    }

    private var parameters: some View {
        HStack(spacing: 20) {
            Menu {
                Toggle("Stay in key", isOn: $instrument.quantized)
                Picker("Key", selection: $instrument.rootNote) {
                    ForEach(0..<12, id: \.self) { Text("\(notes[$0]) minor").tag($0) }
                }.disabled(!instrument.quantized)
            } label: {
                HStack(spacing: 5) {
                    Text(instrument.quantized ? "\(notes[instrument.rootNote]) minor" : "Free pitch")
                    Image(systemName: "chevron.down").font(.system(size: 7))
                }.font(WispType.ui(12))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(WispSurface.mutedText).accessibilityLabel("Pitch and key")
            Button {
                instrument.echo.toggle()
                fieldFocused = true
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(instrument.echo ? WispSurface.ink : WispSurface.mutedText.opacity(0.35))
                        .frame(width: 4, height: 4)
                    Text("Echo").font(WispType.ui(12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(instrument.echo ? WispSurface.ink : WispSurface.mutedText)
            .accessibilityLabel("Echo").accessibilityValue(instrument.echo ? "On" : "Off")
            Spacer()
            Image(systemName: "speaker.wave.1").font(.system(size: 10)).foregroundStyle(WispSurface.mutedText)
            Slider(value: $instrument.volume, in: 0...0.5).controlSize(.mini).tint(WispSurface.mutedText)
                .frame(width: 72).accessibilityLabel("Instrument volume")
                .help("Volume for the live instrument and loop")
        }
    }

    private var phraseControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            WispSurface.divider.opacity(0.6).frame(height: 0.5).padding(.top, 2)
            HStack(spacing: 16) {
                Button {
                    if instrument.isRecording {
                        instrument.finishRecording()
                    } else if instrument.hasLoop && instrument.currentPhraseID == nil {
                        pendingPhraseID = nil
                        replaceUnsaved = true
                    } else {
                        beginRecording()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: instrument.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 11))
                        Text(instrument.isRecording ? "Finish" : instrument.hasLoop ? "New" : "Record")
                    }
                }
                .foregroundStyle(instrument.isRecording ? WispSurface.amber : WispSurface.ink)
                .disabled(instrument.isPreparingLoop)
                .help(instrument.isRecording ? "Finish this phrase and loop it" : "Record up to 30 seconds of the theremin")
                .accessibilityLabel(instrument.isRecording ? "Finish recording" : "Record new phrase")

                Button { instrument.toggleLoopPlayback() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: instrument.isLoopPlaying ? "stop.fill" : "repeat")
                            .font(.system(size: 10))
                        Text(instrument.isLoopPlaying ? "Stop" : "Loop")
                    }
                }
                .disabled(!instrument.hasLoop || instrument.isRecording || instrument.isPreparingLoop)
                .accessibilityLabel(instrument.isLoopPlaying ? "Stop phrase loop" : "Play phrase loop")

                Button { instrument.saveLoop() } label: {
                    Text(instrument.isSavingPhrase ? "Saving…" : instrument.currentPhraseID == nil ? "Save" : "Saved")
                }
                .disabled(!instrument.hasLoop || instrument.isRecording || instrument.isSavingPhrase || instrument.currentPhraseID != nil)
                .help("Keep this theremin phrase for another session")
                .accessibilityLabel(instrument.currentPhraseID == nil ? "Save phrase" : "Phrase saved")

                Spacer(minLength: 0)

                Menu {
                    ForEach(instrument.savedPhrases) { phrase in
                        Button("\(phrase.name) · \(durationLabel(phrase.duration))") {
                            if instrument.hasLoop && instrument.currentPhraseID == nil {
                                pendingPhraseID = phrase.id
                                replaceUnsaved = true
                            } else { instrument.loadPhrase(id: phrase.id) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("Saved")
                        Image(systemName: "chevron.down").font(.system(size: 7))
                    }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(instrument.savedPhrases.isEmpty || instrument.isRecording || instrument.isPreparingLoop)
                .accessibilityLabel("Reopen saved phrase")

                Menu {
                    Button(instrument.isLoopMuted ? "Unmute loop" : "Mute loop") { instrument.toggleLoopMute() }
                    Button("Clear phrase", role: .destructive) { instrument.removeLoop() }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 16, height: 20)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(!instrument.hasLoop || instrument.isRecording || instrument.isPreparingLoop)
                .accessibilityLabel("Phrase options")
            }
            .font(WispType.ui(12)).buttonStyle(.plain)

            HStack {
                Text(phraseStatus)
                Spacer()
                Text("Theremin only")
            }
            .font(WispType.readout(12)).foregroundStyle(WispSurface.mutedText)
            .monospacedDigit()
        }
    }

    private var phraseStatus: String {
        if instrument.isRecording { return "\(durationLabel(instrument.recordingElapsed)) / 0:30" }
        if instrument.isPreparingLoop { return "Preparing phrase…" }
        guard instrument.hasLoop else { return "One phrase, ready to keep" }
        let activity = instrument.isLoopMuted ? "Muted" : instrument.isLoopPlaying ? "Looping" : "Ready"
        return "\(durationLabel(instrument.loopDuration)) · \(activity)"
    }

    private var padColor: Color {
        switch instrument.sound {
        case .air: return WispSurface.cyan
        case .pulse: return WispSurface.amber
        case .glass: return WispSurface.magenta
        }
    }

    private var secondaryPadColor: Color {
        instrument.sound == .air ? WispSurface.magenta : WispSurface.cyan
    }

    private var field: some View {
        GeometryReader { geometry in
            let x = point.x * geometry.size.width
            let y = point.y * geometry.size.height
            ZStack {
                WispSurface.sidebar
                RadialGradient(colors: [padColor.opacity(instrument.active ? 0.18 + 0.12 * (1 - point.y) : 0.055), .clear],
                               center: UnitPoint(x: point.x, y: point.y), startRadius: 0, endRadius: instrument.active ? 175 : 130)
                RadialGradient(colors: [secondaryPadColor.opacity(instrument.active ? 0.12 : 0.025), .clear],
                               center: UnitPoint(x: 1 - point.x, y: min(1, point.y + 0.2)), startRadius: 0, endRadius: 210)

                if !reduceMotion && trail.count > 1 {
                    Path { path in
                        path.addLines(trail.map { CGPoint(x: $0.x * geometry.size.width, y: $0.y * geometry.size.height) })
                    }
                    .stroke(LinearGradient(colors: [padColor.opacity(0.04), padColor.opacity(0.6)],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .opacity(trailOpacity)
                }

                Circle().stroke(padColor.opacity(instrument.active ? 0.16 : 0.06), lineWidth: 0.6)
                    .frame(width: 102, height: 102).position(x: x, y: y)
                Circle().stroke(padColor.opacity(instrument.active ? 0.07 : 0.025), lineWidth: 0.5)
                    .frame(width: 192, height: 192).position(x: x, y: y)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }.stroke(padColor.opacity(instrument.active ? 0.12 : 0.045), lineWidth: 0.5)
                Circle().fill(instrument.active ? padColor : WispSurface.mutedText.opacity(0.65))
                    .frame(width: instrument.active ? 8 : 5, height: instrument.active ? 8 : 5)
                    .shadow(color: padColor.opacity(instrument.active ? 0.55 : 0), radius: 14)
                    .position(x: x, y: y)

                VStack {
                    HStack { Spacer(); Text("BRIGHTER ↑") }
                    Spacer()
                    HStack { Text("← LOWER"); Spacer(); Text("SPACE / HOLD"); Spacer(); Text("HIGHER →") }
                }
                .font(WispType.readout(12)).tracking(0.35)
                .foregroundStyle(WispSurface.mutedText.opacity(0.8)).padding(13)
            }
            .clipped()
            .overlay(alignment: .top) { WispSurface.divider.opacity(0.6).frame(height: 0.5) }
            .overlay(alignment: .bottom) { WispSurface.divider.opacity(0.6).frame(height: 0.5) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                fieldFocused = true
                point = CGPoint(x: min(1, max(0, value.location.x / geometry.size.width)),
                                y: min(1, max(0, value.location.y / geometry.size.height)))
                playPoint()
            }.onEnded { _ in instrument.release() })
            .focusable().focused($fieldFocused).focusEffectDisabled()
            .onKeyPress(.space, phases: [.down, .up]) { press in
                if press.phase == .up { instrument.release() }
                else { playPoint() }
                return .handled
            }
            .onKeyPress(.leftArrow) { movePitch(-0.025); return .handled }
            .onKeyPress(.rightArrow) { movePitch(0.025); return .handled }
            .onKeyPress(.upArrow) { moveBrightness(-0.05); return .handled }
            .onKeyPress(.downArrow) { moveBrightness(0.05); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Theremin field")
            .accessibilityValue(instrument.active ? instrument.noteName : "Ready")
            .accessibilityHint("Hold Space to sound a note. Use left and right arrows for pitch, up and down for brightness.")
            .accessibilityAdjustableAction { direction in
                movePitch(direction == .increment ? 0.05 : -0.05)
            }
        }.frame(height: 252)
    }

    private func playPoint() {
        if !reduceMotion {
            if !instrument.active { trail.removeAll() }
            if let last = trail.last {
                if hypot(last.x - point.x, last.y - point.y) > 0.003 { trail.append(point) }
            } else { trail.append(point) }
            if trail.count > 32 { trail.removeFirst(trail.count - 32) }
            trailOpacity = 1
        }
        instrument.touch(x: point.x, y: 1 - point.y)
    }

    private func fadeTrail() {
        if reduceMotion { trailOpacity = 0 }
        else { withAnimation(.easeOut(duration: 0.45)) { trailOpacity = 0 } }
    }

    private func movePitch(_ delta: CGFloat) {
        point.x = min(1, max(0, point.x + delta))
        if instrument.active { playPoint() }
    }

    private func moveBrightness(_ delta: CGFloat) {
        point.y = min(1, max(0, point.y + delta))
        if instrument.active { playPoint() }
    }

    private func beginRecording() {
        instrument.beginRecording()
        fieldFocused = true
    }

    private func durationLabel(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
