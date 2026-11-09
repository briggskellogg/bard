import SwiftUI
import WispCore

@MainActor
struct QueueView: View {
    @EnvironmentObject private var player: PlayerStore
    let close: () -> Void
    var embedded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if player.queue.isEmpty {
                if embedded {
                    Text("Your next tracks appear here.")
                        .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                } else {
                    EmptyMessage(title: "Empty", message: "Play a track to start a queue.", symbol: "list.bullet")
                }
            } else {
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                        row(track, index: index)
                            .listRowInsets(EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { offsets, destination in
                        player.moveQueued(fromOffsets: offsets, toOffset: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 49)
                .accessibilityLabel("Playback queue")
            }
        }
        .frame(maxHeight: .infinity)
        .background(embedded ? WispSurface.main : WispSurface.sidebar)
    }

    @ViewBuilder
    private var header: some View {
        if embedded {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Queue").font(WispType.ui(12, weight: .medium))
                        .foregroundStyle(WispSurface.ink)
                    Spacer()
                    Text("\(player.queue.count)")
                        .font(WispType.ui(11)).monospacedDigit()
                        .foregroundStyle(WispSurface.mutedText)
                }
                Text("Drag to reorder")
                    .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
            }
            .padding(.horizontal, 24).padding(.top, 23).padding(.bottom, 14)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("THE SESSION").font(WispType.readout(14)).tracking(1.5).foregroundStyle(WispSurface.cyan)
                        Text("Queue").font(WispType.display(25))
                    }
                    Spacer()
                    Text("\(player.queue.count)").font(WispType.readout(16)).foregroundStyle(.secondary)
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help("Close queue").accessibilityLabel("Close queue")
                }
                Text("Drag tracks to change what plays next.")
                    .font(WispType.ui(11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)
        }
    }

    private func row(_ track: Track, index: Int) -> some View {
        let isCurrent = player.currentID == track.id
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .frame(width: 9)
                .help("Drag to reorder")
                .accessibilityHidden(true)
            Text(String(format: "%02d", index + 1))
                .font(WispType.readout(14))
                .foregroundStyle(isCurrent ? WispSurface.cyan : Color.secondary.opacity(0.6))
                .frame(width: 17, alignment: .leading)
                .accessibilityHidden(true)
            Button { player.playQueued(id: track.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.displayTitle)
                        .font(WispType.ui(12, weight: isCurrent ? .medium : .regular))
                        .foregroundStyle(WispSurface.ink)
                        .lineLimit(1)
                    Text(trackSubtitle(track)).font(WispType.ui(10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(track.displayTitle)")
            if isCurrent {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WispSurface.cyan)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("Current track")
            } else {
                Button { player.removeQueued(id: track.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Remove from queue").accessibilityLabel("Remove \(track.displayTitle) from queue")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 9)
        .background(isCurrent ? WispSurface.cyan.opacity(0.045) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Play now") { player.playQueued(id: track.id) }
            AddToMixtapeButton(trackIDs: [track.id])
            Divider()
            Button("Move earlier") { player.moveQueued(id: track.id, offset: -1) }.disabled(index == 0)
            Button("Move later") { player.moveQueued(id: track.id, offset: 1) }.disabled(index == player.queueIDs.count - 1)
            if !isCurrent {
                Divider()
                Button("Remove from queue") { player.removeQueued(id: track.id) }
            }
        }
        .accessibilityAction(named: "Move earlier") { player.moveQueued(id: track.id, offset: -1) }
        .accessibilityAction(named: "Move later") { player.moveQueued(id: track.id, offset: 1) }
    }
}
