import Combine
import Foundation
import WispCore

/// Local listening history is independent of the editable music library.
/// Only measured playback advances this ledger; imported metadata is never history.
@MainActor
final class ListeningStore: ObservableObject {
    @Published private(set) var history: ListeningHistory
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAvailable = true

    private let repository: ListeningRepository
    private var pending: ListeningHistory
    private var session: ListeningSessionAccumulator?
    private var sessionTrack: Track?
    private var canRecord = true
    private var dirty = false
    private var lastPublished: TimeInterval = 0
    private var lastPersisted: TimeInterval = 0

    init(directory: URL) {
        repository = ListeningRepository(directory: directory)
        let empty = ListeningHistory()
        history = empty
        pending = empty
        do {
            let loaded = try repository.load()
            history = loaded
            pending = loaded
        } catch {
            // Keep an unreadable or newer ledger untouched. Never replace history
            // with an empty document just because it could not be opened.
            canRecord = false
            isAvailable = false
            errorMessage = "Listening history could not be opened. The saved file is untouched. \(error.localizedDescription)"
            return
        }
        if !FileManager.default.fileExists(atPath: repository.fileURL.path) {
            dirty = true
            flush()
        }
    }

    func beginOrResume(track: Track, duration: Double, position: Double,
                       uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
                       newRun: Bool = false) {
        guard canRecord else { return }
        if newRun || session == nil || sessionTrack?.id != track.id {
            session = ListeningSessionAccumulator(duration: duration)
        }
        sessionTrack = track
        session?.resetBaseline(position: position, uptime: uptime)
    }

    func sample(position: Double, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
                at date: Date = Date(), track: Track? = nil) {
        guard canRecord, var current = session, let original = sessionTrack else { return }
        let sample = current.sample(position: position, uptime: uptime)
        session = current
        if let track, track.id == original.id { sessionTrack = track }
        guard sample.seconds > 0 || sample.qualifiedPlay else { return }
        pending.record(track: sessionTrack ?? original, seconds: sample.seconds,
                       qualifiedPlay: sample.qualifiedPlay, at: date)
        dirty = true
        // The player samples four times a second. The data window and disk do not
        // need to update at that rate; lifecycle boundaries flush immediately.
        if sample.qualifiedPlay || uptime - lastPublished >= 5 {
            history = pending
            lastPublished = uptime
        }
        if uptime - lastPersisted >= 15 { flush() }
    }

    func resetBaseline(position: Double, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        session?.resetBaseline(position: position, uptime: uptime)
    }

    func end() {
        session = nil
        sessionTrack = nil
        flush()
    }

    func flush() {
        guard canRecord, dirty else { return }
        history = pending
        lastPublished = ProcessInfo.processInfo.systemUptime
        lastPersisted = lastPublished
        do {
            try repository.save(pending)
            dirty = false
            errorMessage = nil
        } catch ListeningHistoryError.changedExternally {
            canRecord = false
            errorMessage = "Listening history changed outside this session. Reopen Bard to reload it; the saved history is untouched."
        } catch ListeningHistoryError.notLoaded {
            canRecord = false
            errorMessage = "Reopen Bard to reload listening history. The saved file is untouched."
        } catch {
            errorMessage = "Listening stats could not be saved. Bard will try again. \(error.localizedDescription)"
        }
    }
}
