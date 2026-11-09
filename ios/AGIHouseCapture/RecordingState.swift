import CoreMedia
import CoreVideo
import Foundation

enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case finalizing
    case saved(URL)
    case failed(String)

    var isRecording: Bool {
        switch self {
        case .starting, .recording:
            true
        default:
            false
        }
    }
}

struct PrivacyDiagnostics: Equatable, Sendable {
    var sanitizedFrames = 0
    var detectedFaces = 0
    var fullFrameFallbacks = 0
}

/// A frame rendered into a separate output buffer after the privacy pass.
/// AVAssetWriter only accepts this type; camera buffers cannot be appended directly.
struct SanitizedFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let detectedFaceCount: Int
    let usedFullFrameFallback: Bool
}
