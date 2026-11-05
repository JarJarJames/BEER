import Foundation

/// Downloads a URL to a file and reports bytes as they arrive, for downloads
/// big enough that a spinner alone looks frozen.
enum FileDownload {
    /// Downloads `source` to `destination`, replacing it, and returns the
    /// server's response. The file is only written for a successful (2xx)
    /// answer; the caller checks the status. `progress` gets (bytes received,
    /// bytes expected, 0 when the server doesn't say), off the main actor.
    /// `configuration` is swappable so tests can serve the bytes themselves.
    static func run(
        from source: URL,
        to destination: URL,
        configuration: URLSessionConfiguration = .default,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URLResponse {
        let delegate = Delegate(destination: destination, progress: progress)
        // A nil queue gives the session its own serial one, so the delegate's
        // state is only touched from there.
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: source)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        let progress: @Sendable (Int64, Int64) -> Void
        var continuation: CheckedContinuation<URLResponse, Error>?
        private var moveError: Error?
        private var lastReported: Int64 = 0

        init(destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
            self.destination = destination
            self.progress = progress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let expected = max(totalBytesExpectedToWrite, 0)
            let step = expected > 0 ? max(expected / FileDownloadLimits.progressSteps, 1) : FileDownloadLimits.unknownSizeStepBytes
            guard totalBytesWritten - lastReported >= step || totalBytesWritten == expected else { return }
            lastReported = totalBytesWritten
            progress(totalBytesWritten, expected)
        }

        /// The temporary file is deleted when this returns, so it's moved here.
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                moveError = error
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error ?? moveError {
                continuation?.resume(throwing: error)
            } else if let response = task.response {
                continuation?.resume(returning: response)
            } else {
                continuation?.resume(throwing: URLError(.badServerResponse))
            }
            continuation = nil
        }
    }
}
