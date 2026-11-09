@preconcurrency import AVFoundation
import Foundation

struct RecordingValidation: Sendable {
    let durationSeconds: Double
    let fileSizeBytes: Int64
}

enum RecordingValidator {
    static func validate(_ url: URL) async throws -> RecordingValidation {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)

        guard videoTracks.count == 1 else {
            throw RecordingValidationError.invalidVideoTrackCount
        }
        guard audioTracks.isEmpty else {
            throw RecordingValidationError.audioTrackPresent
        }
        guard duration.isNumeric, duration.seconds > 0 else {
            throw RecordingValidationError.invalidDuration
        }

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resourceValues.fileSize ?? 0)
        guard fileSize > 0 else {
            throw RecordingValidationError.emptyFile
        }

        return RecordingValidation(
            durationSeconds: duration.seconds,
            fileSizeBytes: fileSize
        )
    }
}

private enum RecordingValidationError: LocalizedError {
    case invalidVideoTrackCount
    case audioTrackPresent
    case invalidDuration
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidVideoTrackCount:
            "The finalized episode does not contain exactly one video track."
        case .audioTrackPresent:
            "The finalized episode unexpectedly contains audio."
        case .invalidDuration:
            "The finalized episode has an invalid duration."
        case .emptyFile:
            "The finalized episode file is empty."
        }
    }
}
