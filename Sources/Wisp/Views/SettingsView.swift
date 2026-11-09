import SwiftUI
import AppKit
import WispCore

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var listening: ListeningStore
    @Bindable private var theme = WispTheme.shared
    @State private var recoveryPresented = false
    @State private var period: ListeningPeriod = .month
    @State private var breakdown: ListeningBreakdown = .tracks

    var body: some View {
        let summary = listening.history.summary(period: period)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Data")
                        .font(WispType.ui(20, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                    Text("Listening in Bard")
                        .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                }
                Spacer()
                Picker("Date range", selection: $period) {
                    ForEach(ListeningPeriod.allCases) { range in Text(range.title).tag(range) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                .accessibilityLabel("Listening date range")
            }
            .padding(.bottom, 25)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if listening.isAvailable {
                        listeningMetrics(summary)
                    } else {
                        Text("Listening history unavailable")
                            .font(WispType.ui(14, weight: .medium))
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let message = listening.errorMessage {
                        Text(message)
                            .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if listening.isAvailable && (summary.totalSeconds > 0 || summary.totalPlays > 0) {
                        if summary.days.count > 1 { activity(summary) }
                        ranking(summary)
                    } else if listening.isAvailable {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("No listening recorded in this period.")
                                .foregroundStyle(WispSurface.ink)
                            Text("Play music in Bard and your time, tracks, and artists will appear here.")
                                .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                    }
                    if listening.isAvailable { coverage }
                    WispSurface.divider.frame(height: 1)
                    PhoneSyncSettingsView()
                    WispSurface.divider.frame(height: 1)
                    DriveSyncSettingsView()
                    WispSurface.divider.frame(height: 1)
                    library
                }
                .padding(.trailing, 4)
            }
            .scrollIndicators(.automatic)

            HStack {
                WispBrandSignature(height: 20)
                Spacer()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.9")")
                    .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
            }
            .padding(.top, 22)
        }
        .padding(28)
        .font(WispType.ui(12))
        .foregroundStyle(WispSurface.ink)
        .frame(width: 620, height: 640)
        .background(WispSurface.main)
        .navigationTitle("Data")
        .tint(PaletteColor.blue.color)
        .modifier(WispAppearancePolicy(theme: theme))
        .confirmationDialog("Recover", isPresented: $recoveryPresented, titleVisibility: .visible) {
            Button("Recover") { store.recoverPrevious() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore the previous saved library? The current record will be preserved, and no audio will be deleted.")
        }
    }

    private func listeningMetrics(_ summary: ListeningSummary) -> some View {
        HStack(alignment: .top, spacing: 20) {
            metric("Time listened", value: ListeningDataFormat.duration(summary.totalSeconds))
                .frame(maxWidth: .infinity, alignment: .leading)
            metric("Plays", value: summary.totalPlays.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)
            metric("Different tracks", value: summary.uniqueTracks.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(WispType.ui(25, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
        }
        .accessibilityElement(children: .combine)
    }

    private func activity(_ summary: ListeningSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Activity").font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
            ListeningActivityView(days: summary.days)
        }
    }

    private func ranking(_ summary: ListeningSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Most listened").font(WispType.ui(13, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("Breakdown", selection: $breakdown) {
                    ForEach(ListeningBreakdown.allCases) { group in Text(group.title).tag(group) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                .accessibilityLabel("Listening breakdown")
            }
            let rows = rankingRows(summary)
            ForEach(Array(rows.prefix(10).enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .center, spacing: 12) {
                    Text((index + 1).formatted())
                        .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                        .frame(width: 18, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).lineLimit(1).truncationMode(.middle)
                        if let subtitle = row.subtitle {
                            Text(subtitle).font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 10)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(ListeningDataFormat.duration(row.seconds))
                            .font(WispType.ui(11)).monospacedDigit()
                        Text("\(row.plays.formatted()) \(row.plays == 1 ? "play" : "plays")")
                            .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 2)
                .help("\(row.title) · \(ListeningDataFormat.duration(row.seconds)) · \(row.plays) plays")
                .accessibilityElement(children: .combine)
            }
            Text("Ranked by time listened\(rows.count > 10 ? " · Top 10 of \(rows.count.formatted())" : "")")
                .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                .padding(.top, 2)
        }
    }

    private func rankingRows(_ summary: ListeningSummary) -> [ListeningDataRow] {
        if breakdown == .tracks {
            return summary.tracks.map { track in
                let current = store.track(id: track.id)
                let title = current?.displayTitle ?? track.title
                let artist = current?.artist ?? track.artist
                return ListeningDataRow(id: track.id.uuidString, title: title,
                                        subtitle: artist.isEmpty ? "Unknown artist" : artist,
                                        seconds: track.seconds, plays: track.plays)
            }
        }
        let groups: [ListeningGroupStat]
        switch breakdown {
        case .tracks: groups = []
        case .artists: groups = summary.artists
        case .origins: groups = summary.origins
        case .genres: groups = summary.genres
        }
        return groups.map { ListeningDataRow(id: $0.id, title: $0.name, subtitle: nil, seconds: $0.seconds, plays: $0.plays) }
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recorded on this Mac since \(listening.history.trackingStartedAt.formatted(date: .abbreviated, time: .omitted)).")
            Text("A play counts after 30 seconds, or halfway through a shorter track. Listening time excludes pauses and seeking.")
            Text("Apple Music and iPhone listening are not included.")
        }
        .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Library").font(WispType.ui(13, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(store.tracks.count.formatted()) tracks · \(ByteCountFormatter.string(fromByteCount: store.storageBytes, countStyle: .file))")
                    .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                    .monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(store.directory.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                    .textSelection(.enabled).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Reveal in Finder") { NSWorkspace.shared.open(store.directory) }
                    .buttonStyle(.plain).foregroundStyle(WispSurface.cyan)
                    .font(WispType.ui(11)).fixedSize()
            }
            Text("Imported music is copied here. Your original files stay untouched.")
                .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            if !store.canEdit && store.hasPreviousIndex {
                VStack(alignment: .leading, spacing: 7) {
                    Button("Recover previous library") { recoveryPresented = true }
                        .buttonStyle(.plain).foregroundStyle(WispSurface.cyan)
                    Text("Restore the previous saved library. The current record will be preserved.")
                        .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private enum ListeningBreakdown: String, CaseIterable, Identifiable {
    case tracks, artists, origins, genres
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct ListeningDataRow: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var seconds: Double
    var plays: Int
}

private enum ListeningDataFormat {
    static func duration(_ seconds: Double) -> String {
        let value = Int(min(Double(Int.max - 1024), max(0, seconds.isFinite ? seconds : 0)).rounded(.down))
        if value < 60 { return "\(value)s" }
        let minutes = value / 60
        if minutes < 60 { return "\(minutes)m \(value % 60)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct ListeningActivityView: View {
    var days: [ListeningDayStat]

    private var buckets: [ActivityBucket] {
        let size = max(1, Int(ceil(Double(days.count) / 45)))
        return stride(from: 0, to: days.count, by: size).map { start in
            let end = min(start + size, days.count)
            let slice = days[start..<end]
            return ActivityBucket(date: days[start].date, endDate: days[end - 1].date,
                                  seconds: slice.reduce(0) { $0 + $1.seconds })
        }
    }

    var body: some View {
        let values = buckets
        let maximum = max(1, values.map(\.seconds).max() ?? 1)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values) { bucket in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(bucket.seconds > 0 ? WispSurface.cyan.opacity(0.65) : WispSurface.divider)
                        .frame(maxWidth: .infinity)
                        .frame(height: bucket.seconds > 0 ? max(3, 42 * bucket.seconds / maximum) : 1)
                        .frame(height: 42, alignment: .bottom)
                        .help(bucket.label)
                        .accessibilityLabel(bucket.label)
                }
            }
            HStack {
                Text(days.first?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")
                Spacer()
                Text(days.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")
            }
            .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Listening activity")
    }

    private struct ActivityBucket: Identifiable {
        var date: Date
        var endDate: Date
        var seconds: Double
        var id: Date { date }
        var label: String {
            let first = date.formatted(date: .abbreviated, time: .omitted)
            let range = date == endDate ? first : "\(first) – \(endDate.formatted(date: .abbreviated, time: .omitted))"
            return "\(range): \(ListeningDataFormat.duration(seconds))"
        }
    }
}
