import AVKit
import SwiftUI
import WispCore

struct PhonePlayerView: View {
    @EnvironmentObject private var player: PhonePlayerStore
    @EnvironmentObject private var library: PhoneLibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var seeking = false
    @State private var seekPosition = 0.0
    @State private var seekTrack: Track?
    @State private var showQueue = false
    @State private var showShuffle = false
    @ScaledMetric(relativeTo: .title2) private var coverSize = 56.0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        Group {
                            if geometry.size.width > 600 && geometry.size.width > geometry.size.height {
                                HStack(spacing: 32) {
                                    aura.frame(maxWidth: .infinity)
                                    controls.frame(maxWidth: 460)
                                }
                            } else {
                                VStack(spacing: 24) {
                                    aura.frame(height: min(230, max(120, geometry.size.height * 0.29)))
                                    controls
                                }.frame(maxWidth: 540)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 26).padding(.vertical, 16)
                        .frame(minHeight: max(0, geometry.size.height - 56))
                    }.scrollBounceBehavior(.basedOnSize)
                }.background(PhoneStyle.background)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showQueue) { PhoneQueueView() }
            .sheet(isPresented: $showShuffle) { PhoneSmartShuffleView(tracks: player.queue, title: "Current queue") }
        }
        .onChange(of: player.currentTrack) { _, _ in
            // Do not reinterpret an unfinished seek gesture for a new song.
            seekTrack = nil; seekPosition = player.position
        }
        .alert("Playback", isPresented: Binding(get: { !showQueue && !showShuffle && player.errorMessage != nil }, set: {
            if !$0 { player.errorMessage = nil }
        })) {
            Button("OK") { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .medium)).frame(width: 44, height: 44)
            }.accessibilityLabel("Close player")
            Spacer()
            Text("Now Playing").font(.wispText(.small, medium: true)).foregroundStyle(PhoneStyle.muted)
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 17)).frame(width: 44, height: 44)
            }.accessibilityLabel("Queue")
        }.foregroundStyle(PhoneStyle.muted).padding(.horizontal, 12).padding(.top, 10)
    }

    private var aura: some View {
        PhonePlayerAura(meters: player.meters, playing: player.isPlaying).frame(minHeight: 110)
    }

    private var controls: some View {
        VStack(spacing: 22) {
            if let track = player.currentTrack {
                HStack(alignment: .center, spacing: 18) {
                    if let source = sourceURL(track) {
                        Button { openURL(source) } label: {
                            PhoneCover(url: player.currentArtworkURL, size: min(90, coverSize)).rotationEffect(.degrees(-2))
                        }.buttonStyle(PhoneArtworkPressStyle())
                            .accessibilityLabel("Open original source for \(track.displayTitle)")
                    } else {
                        PhoneCover(url: player.currentArtworkURL, size: min(90, coverSize)).rotationEffect(.degrees(-2))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(track.displayTitle).font(.wispText(.title, medium: true)).fixedSize(horizontal: false, vertical: true)
                            Button { library.toggleFavorite(track) } label: {
                                Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                                    .font(.system(size: 15))
                                    .foregroundStyle(library.isFavorite(track) ? PhoneStyle.rose : Color.secondary)
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(library.isFavorite(track) ? "Remove from favorites" : "Add to favorites")
                                .disabled(!library.document.tracks.contains { $0.id == track.id })
                        }
                        if !track.artist.isEmpty { Text(track.artist).font(.wispText(.caption)).foregroundStyle(.secondary) }
                        if !track.displayOrigin.isEmpty {
                            Text(track.displayOrigin).font(.wispText(.small)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            progress
            HStack {
                Spacer()
                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill").font(.system(size: 23)).frame(width: 56, height: 64)
                }.accessibilityLabel("Previous song")
                Spacer()
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 29, weight: .semibold)).frame(width: 72, height: 72)
                        .foregroundStyle(PhoneStyle.blue)
                        .background(PhoneStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }.buttonStyle(PhoneArtworkPressStyle()).accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").font(.system(size: 23)).frame(width: 56, height: 64)
                }.accessibilityLabel("Next song")
                Spacer()
            }.foregroundStyle(.primary).disabled(player.currentTrack == nil)
            HStack {
                Button { player.cycleRepeatMode() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 17)).frame(width: 44, height: 44)
                        .foregroundStyle(player.repeatMode == .off ? Color.secondary : PhoneStyle.blue)
                }
                .accessibilityLabel("Repeat")
                .accessibilityValue(player.repeatMode == .off ? "Off" : player.repeatMode == .one ? "One song" : "All songs")
                Spacer()
                Button { showShuffle = true } label: {
                    Label("Smart Shuffle", systemImage: "waveform.path").font(.wispText(.small, medium: true)).frame(minHeight: 44)
                }.disabled(player.queue.isEmpty)
                Spacer()
                PhoneAudioOutputPicker().frame(width: 44, height: 44)
            }
            HStack {
                Image("wisp-wordmark").resizable().scaledToFit().frame(width: 43, height: 24).opacity(0.75).accessibilityHidden(true)
                Spacer()
                if let index = player.currentQueueIndex {
                    Text("\(index + 1) / \(player.queue.count)").font(.wisp(10)).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("Song \(index + 1) of \(player.queue.count)")
                }
                Spacer()
                Image("maker-mark").resizable().scaledToFit().frame(width: 13, height: 19).accessibilityHidden(true)
            }.padding(.bottom, 4)
        }
    }

    private var progress: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { displayedPosition }, set: { value in
                seekPosition = value
                if !seeking { player.seek(to: value) }
            }), in: 0...max(1, player.duration)) { editing in
                if editing {
                    seekTrack = player.currentTrack; seekPosition = player.position; seeking = true
                } else {
                    let original = seekTrack
                    seekTrack = nil; seeking = false
                    guard let original, original == player.currentTrack else { return }
                    player.seek(to: seekPosition)
                }
            }.accessibilityLabel("Playback position").disabled(player.currentTrack == nil)
            HStack {
                Text(time(displayedPosition))
                Spacer()
                Text("−" + time(max(0, player.duration - displayedPosition)))
            }.font(.wispTiming(10)).foregroundStyle(.secondary)
        }
    }
    private var displayedPosition: Double {
        seeking && seekTrack == player.currentTrack ? seekPosition : player.position
    }
    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
    private func sourceURL(_ track: Track) -> URL? {
        guard let source = track.sourceURL, let url = URL(string: source),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else { return nil }
        return url
    }
}

struct PhoneQueueView: View {
    @EnvironmentObject private var player: PhonePlayerStore
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                        Button { player.selectQueueTrack(id: track.id) } label: {
                            HStack(spacing: 13) {
                                PhoneCover(url: player.artworkURL(for: track), size: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.displayTitle).font(.wispText(.caption, medium: true)).foregroundStyle(.primary).lineLimit(2)
                                    Text(track.artist).font(.wispText(.small)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 5)
                                if track.id == player.currentTrack?.id {
                                    Image(systemName: "waveform").font(.system(size: 14)).foregroundStyle(PhoneStyle.blue)
                                } else {
                                    Text("\(index + 1)").font(.wisp(10)).monospacedDigit().foregroundStyle(.tertiary)
                                }
                            }.padding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(.plain).id(track.id)
                            .accessibilityLabel("\(track.displayTitle), \(track.artist)\(track.id == player.currentTrack?.id ? ", now playing" : "")")
                            .swipeActions { Button("Remove", role: .destructive) { player.removeFromQueue(ids: [track.id]) } }
                            .listRowBackground(PhoneStyle.background).listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 3, leading: 22, bottom: 3, trailing: 22))
                    }
                    .onMove(perform: player.moveQueue)
                    .onDelete { offsets in
                        let ids = Set(offsets.compactMap { player.queue.indices.contains($0) ? player.queue[$0].id : nil })
                        player.removeFromQueue(ids: ids)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).background(PhoneStyle.background)
                .environment(\.editMode, $editMode)
                .onAppear { if let id = player.currentTrack?.id { proxy.scrollTo(id, anchor: .center) } }
                .overlay { if player.queue.isEmpty { ContentUnavailableView("Your queue is clear", systemImage: "music.note.list") } }
            }
            .navigationTitle("Queue").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode == .active ? "Done" : "Reorder") { withAnimation { editMode = editMode == .active ? .inactive : .active } }
                        .disabled(player.queue.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13)).frame(width: 30, height: 30) }
                        .foregroundStyle(PhoneStyle.muted)
                        .accessibilityLabel("Close queue")
                }
            }
            .alert("Playback", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
                Button("OK") { player.errorMessage = nil }
            } message: { Text(player.errorMessage ?? "") }
        }
    }
}

private struct PhoneArtworkPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct PhoneAudioOutputPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .secondaryLabel
        picker.activeTintColor = UIColor(PhoneStyle.blue)
        picker.accessibilityLabel = "Audio output"
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Only this subtree observes the meter; browsing and artwork stay quiet.
private struct PhonePlayerAura: View {
    @ObservedObject var meters: PhonePlaybackMeters
    var playing: Bool
    var body: some View { PhoneAura(level: meters.level, playing: playing) }
}
