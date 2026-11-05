import Foundation

/// Downloads one file with progress reports and cancellation. The finished file is moved to `destination`.
public final class PackageDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public typealias Progress = @Sendable (_ written: Int64, _ expected: Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var onProgress: Progress = { _, _ in }
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var moveError: Error?
    /// Resume data captured when a download is cancelled or fails partway, so it can continue later.
    public private(set) var resumeData: Data?

    public override init() {}

    public func run(_ url: URL, to destination: URL, resumeFrom: Data? = nil, onProgress: @escaping Progress) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 48 * 3600
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            let task = resumeFrom.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
            lock.lock()
            self.continuation = continuation; self.destination = destination; self.onProgress = onProgress
            self.session = session; self.task = task; self.resumeData = nil
            lock.unlock()
            task.resume()
        }
    }
    /// Cancels and keeps resume data for a later continuation (best effort).
    public func cancel() {
        lock.lock(); let task = task; lock.unlock()
        task?.cancel { [weak self] data in
            guard let self else { return }
            self.lock.lock(); self.resumeData = data; self.lock.unlock()
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock(); let report = onProgress; lock.unlock()
        report(totalBytesWritten, totalBytesExpectedToWrite)
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock(); let target = destination; lock.unlock()
        guard let target else { return }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(domain: "PackageDownload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Apple-Server antwortet mit HTTP \(http.statusCode)."])
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: location, to: target)
        } catch { lock.lock(); moveError = error; lock.unlock() }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation; self.continuation = nil
        let failure = error ?? moveError; let target = destination
        // Keep resume data the server/URL loading system provides on a resumable failure.
        if let data = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { self.resumeData = data }
        self.session = nil; self.task = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        if let failure { continuation?.resume(throwing: failure) } else if let target { continuation?.resume(returning: target) }
    }
}

public enum Gzip {
    /// Decompresses a single-member gzip file (RFC 1952) using the system's raw DEFLATE decoder.
    public static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return data }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { guard offset + 2 <= bytes.count else { throw invalid }; offset += 2 + (Int(bytes[offset]) | Int(bytes[offset + 1]) << 8) }
        if flags & 0x08 != 0 { while offset < bytes.count && bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < bytes.count && bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { throw invalid }
        let deflate = Data(bytes[offset..<(bytes.count - 8)])
        return try (deflate as NSData).decompressed(using: .zlib) as Data
    }
    private static var invalid: NSError { NSError(domain: "Gzip", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple-Katalog ist beschädigt."]) }
}
