import Foundation

enum DownloadServiceError: LocalizedError, Equatable {
    case invalidResponse
    case serverStatus(Int)
    case rangeUnsupported
    case incompleteDownload
    case cancelled
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: L10n.tr("download_invalid_response")
        case let .serverStatus(code): L10n.tr("download_http_error", code)
        case .rangeUnsupported: L10n.tr("range_unsupported")
        case .incompleteDownload: L10n.tr("incomplete_download")
        case .cancelled: L10n.tr("download_cancelled")
        case let .fileSystem(message): L10n.tr("download_file_error", message)
        }
    }
}

final class ParallelDownloadService: @unchecked Sendable {
    typealias ProgressHandler = @MainActor @Sendable (_ completed: Int64, _ total: Int64) -> Void

    func download(
        asset: ReleaseAsset,
        connections: Int,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(AppConstants.supportDirectoryName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        do {
            let archiveURL = root.appendingPathComponent(asset.name)
            let workerCount = max(1, min(AppConstants.Downloads.maximumConnections, connections))

            if workerCount > 1, asset.size >= AppConstants.Network.minimumMultipartSize {
                do {
                    let partURLs = try await runOperation(
                        url: asset.downloadURL,
                        totalBytes: asset.size,
                        parts: workerCount,
                        directory: root,
                        progress: progress
                    )
                    try merge(parts: partURLs, into: archiveURL)
                    partURLs.forEach { try? fileManager.removeItem(at: $0) }
                    return archiveURL
                } catch DownloadServiceError.rangeUnsupported {
                    try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                        .filter { $0.lastPathComponent.hasPrefix("part-") }
                        .forEach { try? fileManager.removeItem(at: $0) }
                }
            }

            let partURLs = try await runOperation(
                url: asset.downloadURL,
                totalBytes: asset.size,
                parts: 1,
                directory: root,
                progress: progress
            )
            guard let source = partURLs.first else { throw DownloadServiceError.incompleteDownload }
            try fileManager.moveItem(at: source, to: archiveURL)
            return archiveURL
        } catch {
            try? fileManager.removeItem(at: root)
            if Task.isCancelled { throw DownloadServiceError.cancelled }
            throw error
        }
    }

    private func runOperation(
        url: URL,
        totalBytes: Int64,
        parts: Int,
        directory: URL,
        progress: @escaping ProgressHandler
    ) async throws -> [URL] {
        let operation = ChunkDownloadOperation(
            url: url,
            totalBytes: totalBytes,
            partCount: parts,
            directory: directory,
            progress: progress
        )
        return try await operation.run()
    }

    private func merge(parts: [URL], into destination: URL) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let output = try? FileHandle(forWritingTo: destination) else {
            throw DownloadServiceError.fileSystem(destination.path)
        }
        defer { try? output.close() }

        for part in parts {
            try Task.checkCancellation()
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            while let data = try input.read(upToCount: AppConstants.Downloads.mergeBufferSize), !data.isEmpty {
                try output.write(contentsOf: data)
            }
        }
    }
}

private final class ChunkDownloadOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Writer {
        let url: URL
        let handle: FileHandle
        let lowerBound: Int64
        let upperBound: Int64
        let expectedBytes: Int64
        var receivedBytes: Int64 = 0

        init(url: URL, handle: FileHandle, lowerBound: Int64, upperBound: Int64, expectedBytes: Int64) {
            self.url = url
            self.handle = handle
            self.lowerBound = lowerBound
            self.upperBound = upperBound
            self.expectedBytes = expectedBytes
        }
    }

    private let url: URL
    private let totalBytes: Int64
    private let partCount: Int
    private let directory: URL
    private let progress: ParallelDownloadService.ProgressHandler
    private let lock = NSLock()
    private var session: URLSession?
    private var tasks: [URLSessionDataTask] = []
    private var writers: [Int: Writer] = [:]
    private var continuation: CheckedContinuation<[URL], Error>?
    private var finished = false
    private var cancelled = false
    private var completedTasks = 0
    private var receivedBytes: Int64 = 0
    private var lastProgressUpdate = Date.distantPast

    init(
        url: URL,
        totalBytes: Int64,
        partCount: Int,
        directory: URL,
        progress: @escaping ParallelDownloadService.ProgressHandler
    ) {
        self.url = url
        self.totalBytes = totalBytes
        self.partCount = max(1, partCount)
        self.directory = directory
        self.progress = progress
    }

    func run() async throws -> [URL] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation: continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(continuation: CheckedContinuation<[URL], Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: DownloadServiceError.cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = AppConstants.Network.downloadRequestTimeout
            configuration.timeoutIntervalForResource = AppConstants.Network.downloadResourceTimeout
            configuration.httpAdditionalHeaders = ["User-Agent": AppConstants.userAgent]
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1
            delegateQueue.qualityOfService = .utility
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
            self.session = session

            let chunkSize = totalBytes / Int64(partCount)
            for index in 0..<partCount {
                let lowerBound = Int64(index) * chunkSize
                let upperBound = index == partCount - 1 ? totalBytes - 1 : lowerBound + chunkSize - 1
                let expected = upperBound - lowerBound + 1
                let partURL = directory.appendingPathComponent(String(format: "part-%03d", index))
                guard FileManager.default.createFile(atPath: partURL.path, contents: nil) else {
                    throw DownloadServiceError.fileSystem(partURL.path)
                }
                let handle = try FileHandle(forWritingTo: partURL)

                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                if partCount > 1 {
                    request.setValue("bytes=\(lowerBound)-\(upperBound)", forHTTPHeaderField: "Range")
                }
                let task = session.dataTask(with: request)
                writers[task.taskIdentifier] = Writer(
                    url: partURL,
                    handle: handle,
                    lowerBound: lowerBound,
                    upperBound: upperBound,
                    expectedBytes: expected
                )
                tasks.append(task)
            }
            tasks.forEach { $0.resume() }
        } catch {
            finish(with: .failure(error))
        }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let shouldFinish = continuation != nil && !finished
        lock.unlock()
        if shouldFinish { finish(with: .failure(DownloadServiceError.cancelled)) }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(with: .failure(DownloadServiceError.invalidResponse))
            return
        }

        let validStatus = partCount > 1 ? response.statusCode == 206 : (200..<300).contains(response.statusCode)
        guard validStatus else {
            completionHandler(.cancel)
            let error: DownloadServiceError = partCount > 1 && response.statusCode == 200
                ? .rangeUnsupported
                : .serverStatus(response.statusCode)
            finish(with: .failure(error))
            return
        }
        if partCount > 1,
           let writer = writers[dataTask.taskIdentifier],
           !contentRange(response.value(forHTTPHeaderField: "Content-Range"), matches: writer) {
            completionHandler(.cancel)
            finish(with: .failure(DownloadServiceError.rangeUnsupported))
            return
        }
        completionHandler(.allow)
    }

    private func contentRange(_ value: String?, matches writer: Writer) -> Bool {
        guard let value else { return false }
        let expectedPrefix = "bytes \(writer.lowerBound)-\(writer.upperBound)/"
        return value.lowercased().hasPrefix(expectedPrefix)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var shouldReport = false
        var currentBytes: Int64 = 0
        lock.lock()
        guard !finished, let writer = writers[dataTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        lock.unlock()

        do {
            try writer.handle.write(contentsOf: data)
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            writer.receivedBytes += Int64(data.count)
            receivedBytes += Int64(data.count)
            currentBytes = receivedBytes
            if Date().timeIntervalSince(lastProgressUpdate) >= AppConstants.Network.progressUpdateInterval
                || currentBytes >= totalBytes {
                lastProgressUpdate = Date()
                shouldReport = true
            }
            lock.unlock()
        } catch {
            finish(with: .failure(DownloadServiceError.fileSystem(error.localizedDescription)))
            return
        }

        if shouldReport {
            Task { @MainActor [progress, totalBytes] in
                progress(currentBytes, totalBytes)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            lock.lock()
            let alreadyFinished = finished
            lock.unlock()
            if !alreadyFinished { finish(with: .failure(error)) }
            return
        }

        lock.lock()
        guard !finished, let writer = writers[task.taskIdentifier] else {
            lock.unlock()
            return
        }
        let validSize = writer.receivedBytes == writer.expectedBytes
        completedTasks += 1
        let allCompleted = completedTasks == partCount
        let orderedURLs = writers.values.map(\.url).sorted { $0.lastPathComponent < $1.lastPathComponent }
        lock.unlock()

        try? writer.handle.close()
        if !validSize {
            finish(with: .failure(DownloadServiceError.incompleteDownload))
        } else if allCompleted {
            Task { @MainActor [progress, totalBytes] in progress(totalBytes, totalBytes) }
            finish(with: .success(orderedURLs))
        }
    }

    private func finish(with result: Result<[URL], Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        let handles = writers.values.map(\.handle)
        let session = self.session
        lock.unlock()

        if case .failure = result { tasks.forEach { $0.cancel() } }
        handles.forEach { try? $0.close() }
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}
