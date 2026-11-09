@preconcurrency import AVFoundation
import Foundation
import Vision

enum ResidualFaceValidator {
    static func validate(
        _ url: URL,
        sampleIntervalSeconds: Double = 0.5
    ) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0 else {
            throw ResidualFaceValidationError.invalidDuration
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var seconds = 0.0
        while seconds < duration.seconds {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let result = try await generator.image(at: time)
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: result.image)
            try handler.perform([request])

            if !(request.results ?? []).isEmpty {
                throw ResidualFaceValidationError.faceDetected(seconds)
            }
            seconds += sampleIntervalSeconds
        }
    }
}

private enum ResidualFaceValidationError: LocalizedError {
    case invalidDuration
    case faceDetected(Double)

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            "The privacy scan could not determine the episode duration."
        case let .faceDetected(seconds):
            "A possible unredacted face remains near \(seconds.formatted(.number.precision(.fractionLength(1)))) seconds."
        }
    }
}
