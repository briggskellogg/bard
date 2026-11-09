import Foundation
import WispCore

struct DownloadedMusic {
    let url: URL
    let directory: URL
}

enum MusicDownloadError: LocalizedError {
    case invalidURL, webpage, response(Int), tooLarge, empty

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a complete http or https download link."
        case .webpage: return "This link opens a webpage. Download the song there, then choose Files to import it with its source link."
        case .response(let status): return "The download server returned \(status). Open the source page to get a current download link."
        case .tooLarge: return "This download exceeds 8 GB. Download it in your browser, then import the files from Finder."
        case .empty: return "The download was empty."
        }
    }
}

private final class DownloadLimit: NSObject, URLSessionDownloadDelegate {
    private let lock = NSLock()
    private var exceeded = false
    var wasExceeded: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if max(totalBytesWritten, totalBytesExpectedToWrite) > 8 * 1024 * 1024 * 1024 {
            lock.lock(); exceeded = true; lock.unlock()
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let valid = request.url.flatMap { MusicSource.validatedURL($0.absoluteString) } != nil
        completionHandler(valid ? request : nil)
    }
}

enum DownloadImporter {
    static func download(_ url: URL) async throws -> DownloadedMusic {
        guard MusicSource.validatedURL(url.absoluteString) != nil else { throw MusicDownloadError.invalidURL }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 900
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let limit = DownloadLimit()
        let session = URLSession(configuration: configuration, delegate: limit, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("audio/*, application/zip, application/octet-stream;q=0.9", forHTTPHeaderField: "Accept")

        let temporary: URL
        let response: URLResponse
        do { (temporary, response) = try await session.download(for: request, delegate: limit) }
        catch {
            if limit.wasExceeded { throw MusicDownloadError.tooLarge }
            throw error
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicDownloadError.response((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let size = (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { throw MusicDownloadError.empty }
        guard size <= 8 * 1024 * 1024 * 1024 else { throw MusicDownloadError.tooLarge }

        let mime = response.mimeType?.lowercased() ?? ""
        let allowed = Set(["mp3", "m4a", "aac", "wav", "aif", "aiff", "aifc", "flac", "caf", "mp4", "ogg", "opus", "zip"])
        var filename = URL(fileURLWithPath: response.suggestedFilename ?? url.lastPathComponent).lastPathComponent
        var ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let mimeExtensions = ["audio/mpeg":"mp3", "audio/mp4":"m4a", "audio/aac":"aac", "audio/wav":"wav",
                              "audio/x-wav":"wav", "audio/flac":"flac", "audio/x-flac":"flac", "audio/aiff":"aiff",
                              "audio/x-aiff":"aiff", "audio/ogg":"ogg", "application/zip":"zip", "application/x-zip-compressed":"zip"]
        if !allowed.contains(ext), let inferred = mimeExtensions[mime] {
            filename += "." + inferred
            ext = inferred
        }
        guard !mime.contains("html"), !mime.contains("json"), !mime.contains("xml"), allowed.contains(ext) else {
            throw MusicDownloadError.webpage
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Wisp-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(filename)
        do { try FileManager.default.moveItem(at: temporary, to: destination) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
        return DownloadedMusic(url: destination, directory: directory)
    }
}

@MainActor
extension LibraryStore {
    @discardableResult
    func importDownload(from url: URL, sourceURL: URL?, into playlistID: UUID?) async -> Bool {
        guard canEdit, !isImporting, importReview == nil else { return false }
        errorMessage = nil
        do {
            let download = try await DownloadImporter.download(url)
            defer { try? FileManager.default.removeItem(at: download.directory) }
            try Task.checkCancellation()
            guard canEdit, !isImporting, importReview == nil else {
                errorMessage = canEdit
                    ? "Another import started while this file was downloading. Finish or cancel its review, then try this link again."
                    : "The library is unavailable. Resolve its error before importing this download."
                return false
            }
            await importFiles([download.url], into: playlistID, sourceURL: sourceURL ?? url)
            return errorMessage == nil
        } catch is CancellationError { return false }
        catch let error as URLError where error.code == .cancelled { return false }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
