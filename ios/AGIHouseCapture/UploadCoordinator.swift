@preconcurrency import AVFoundation
import CryptoKit
import Foundation

actor UploadCoordinator {
    private let baseURL: URL
    private let queueURL: URL
    private let bodyDirectory: URL
    private var queue: [QueuedEpisode]

    init(baseURL: URL) {
        self.baseURL = baseURL

        let fileManager = FileManager.default
        let applicationSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let uploadDirectory = applicationSupport.appendingPathComponent(
            "UploadQueue",
            isDirectory: true
        )
        bodyDirectory = uploadDirectory.appendingPathComponent(
            "Bodies",
            isDirectory: true
        )
        queueURL = uploadDirectory.appendingPathComponent("queue.json")

        try? fileManager.createDirectory(
            at: bodyDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        queue = Self.loadQueue(from: queueURL)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = uploadDirectory
        try? mutableDirectory.setResourceValues(values)
    }

    func enqueue(fileURL: URL, taskID: String) async throws -> Int {
        let validation = try await RecordingValidator.validate(fileURL)
        let checksum = try Self.sha256(of: fileURL)
        let episodeID = UUID().uuidString
        let manifest = EpisodeManifest(
            schemaVersion: "1.0",
            episodeID: episodeID,
            taskID: taskID,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            durationSeconds: validation.durationSeconds,
            width: validation.width,
            height: validation.height,
            nominalFrameRate: validation.nominalFrameRate,
            anonymizerVersion: "vision-face-pixelation-v1"
        )

        queue.append(
            QueuedEpisode(
                episodeID: episodeID,
                filePath: fileURL.path,
                checksumSHA256: checksum,
                manifest: manifest
            )
        )
        try persistQueue()
        return queue.count
    }

    func pendingCount() -> Int {
        queue.count
    }

    func uploadNext() async throws -> (GateResult, Int)? {
        guard let episode = queue.first else { return nil }
        guard FileManager.default.fileExists(atPath: episode.filePath) else {
            queue.removeFirst()
            try persistQueue()
            throw UploadError.episodeFileMissing
        }

        let result = try await upload(episode)
        try? FileManager.default.removeItem(at: episode.fileURL)
        queue.removeFirst()
        try persistQueue()
        return (result, queue.count)
    }

    private func upload(_ episode: QueuedEpisode) async throws -> GateResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        let bodyURL = try makeMultipartBody(for: episode, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: baseURL.appendingPathComponent("episodes"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let (data, response) = try await URLSession.shared.upload(
            for: request,
            fromFile: bodyURL
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw UploadError.serverRejected(httpResponse.statusCode, message)
        }

        return try JSONDecoder().decode(GateResult.self, from: data)
    }

    private func makeMultipartBody(
        for episode: QueuedEpisode,
        boundary: String
    ) throws -> URL {
        let bodyURL = bodyDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("multipart")
        _ = FileManager.default.createFile(atPath: bodyURL.path, contents: nil)

        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }

        try writeField(
            name: "idempotency_key",
            value: episode.episodeID,
            boundary: boundary,
            to: output
        )
        try writeField(
            name: "checksum_sha256",
            value: episode.checksumSHA256,
            boundary: boundary,
            to: output
        )
        let manifestData = try JSONEncoder().encode(episode.manifest)
        guard let manifest = String(data: manifestData, encoding: .utf8) else {
            throw UploadError.cannotEncodeManifest
        }
        try writeField(
            name: "manifest",
            value: manifest,
            boundary: boundary,
            to: output
        )

        let videoHeader =
            "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"video\"; filename=\"episode.mp4\"\r\n" +
            "Content-Type: video/mp4\r\n" +
            "\r\n"
        try output.write(contentsOf: Data(videoHeader.utf8))

        let source = try FileHandle(forReadingFrom: episode.fileURL)
        defer { try? source.close() }
        while let chunk = try source.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))

        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: bodyURL.path
        )
        return bodyURL
    }

    private func writeField(
        name: String,
        value: String,
        boundary: String,
        to output: FileHandle
    ) throws {
        let field =
            "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"\(name)\"\r\n" +
            "\r\n" +
            "\(value)\r\n"
        try output.write(contentsOf: Data(field.utf8))
    }

    private func persistQueue() throws {
        let data = try JSONEncoder().encode(queue)
        try data.write(to: queueURL, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableQueueURL = queueURL
        try mutableQueueURL.setResourceValues(values)
    }

    private static func loadQueue(from url: URL) -> [QueuedEpisode] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([QueuedEpisode].self, from: data)) ?? []
    }

    private static func sha256(of url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }

        var hasher = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private enum UploadError: LocalizedError {
    case episodeFileMissing
    case invalidResponse
    case serverRejected(Int, String)
    case cannotEncodeManifest

    var errorDescription: String? {
        switch self {
        case .episodeFileMissing:
            "A queued episode file is missing."
        case .invalidResponse:
            "The laptop returned an invalid response."
        case let .serverRejected(status, message):
            "The laptop rejected the upload (\(status)): \(message)"
        case .cannotEncodeManifest:
            "The episode manifest could not be encoded."
        }
    }
}
