import Foundation

enum CaptureState: Equatable, Sendable {
    case idle
    case requestingPermission
    case configuring
    case previewing
    case interrupted(String)
    case denied
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "Camera stopped"
        case .requestingPermission:
            "Requesting camera access"
        case .configuring:
            "Starting camera"
        case .previewing:
            "Camera ready"
        case .interrupted:
            "Camera interrupted"
        case .denied:
            "Camera access required"
        case .failed:
            "Camera unavailable"
        }
    }

    var detail: String? {
        switch self {
        case let .interrupted(message), let .failed(message):
            message
        case .denied:
            "Allow camera access in Settings to continue."
        default:
            nil
        }
    }

    var symbolName: String {
        switch self {
        case .previewing:
            "camera.fill"
        case .denied, .failed:
            "exclamationmark.triangle.fill"
        case .interrupted:
            "pause.circle.fill"
        default:
            "camera"
        }
    }
}

struct CaptureDiagnostics: Equatable, Sendable {
    var processedFrames = 0
    var droppedFrames = 0
    var latestTimestampSeconds: Double?
}
