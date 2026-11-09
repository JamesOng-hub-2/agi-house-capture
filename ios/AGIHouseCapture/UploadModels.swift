import Foundation

struct EpisodeManifest: Codable, Sendable {
    let schemaVersion: String
    let episodeID: String
    let taskID: String
    let capturedAt: String
    let durationSeconds: Double
    let width: Int
    let height: Int
    let nominalFrameRate: Float
    let anonymizerVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case episodeID = "episode_id"
        case taskID = "task_id"
        case capturedAt = "captured_at"
        case durationSeconds = "duration_seconds"
        case width
        case height
        case nominalFrameRate = "nominal_frame_rate"
        case anonymizerVersion = "anonymizer_version"
    }
}

struct QueuedEpisode: Codable, Sendable {
    let episodeID: String
    let filePath: String
    let checksumSHA256: String
    let manifest: EpisodeManifest

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}

struct GateResult: Codable, Sendable {
    let id: String
    let taskID: String
    let sizeBytes: Int
    let checksumSHA256: String
    let decision: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case sizeBytes = "size_bytes"
        case checksumSHA256 = "checksum_sha256"
        case decision
        case reason
    }
}

enum UploadState: Equatable, Sendable {
    case idle
    case preparing
    case queued(Int, String?)
    case uploading(Int)
    case completed(decision: String, reason: String)

    var title: String {
        switch self {
        case .idle:
            "No pending uploads"
        case .preparing:
            "Preparing episode"
        case let .queued(count, _):
            "\(count) episode\(count == 1 ? "" : "s") queued"
        case let .uploading(count):
            "Uploading · \(count) queued"
        case let .completed(decision, _):
            "Gate result · \(decision)"
        }
    }

    var detail: String? {
        switch self {
        case let .queued(_, message):
            message
        case let .completed(_, reason):
            reason
        default:
            nil
        }
    }
}
