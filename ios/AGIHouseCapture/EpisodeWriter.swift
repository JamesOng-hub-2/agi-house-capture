@preconcurrency import AVFoundation
import CoreVideo
import Foundation

final class EpisodeWriter: @unchecked Sendable {
    let outputURL: URL

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var hasStarted = false

    init(width: Int, height: Int) throws {
        outputURL = try Self.makeOutputURL()
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: 5_000_000,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]

        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else {
            throw EpisodeWriterError.cannotAddInput
        }
        writer.add(input)
    }

    func makePixelBuffer(startingAt presentationTime: CMTime) throws -> CVPixelBuffer {
        if !hasStarted {
            guard writer.startWriting() else {
                throw writer.error ?? EpisodeWriterError.cannotStart
            }
            writer.startSession(atSourceTime: presentationTime)
            hasStarted = true
        }

        guard let pool = adaptor.pixelBufferPool else {
            throw EpisodeWriterError.pixelBufferPoolUnavailable
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw EpisodeWriterError.cannotAllocatePixelBuffer(status)
        }
        return pixelBuffer
    }

    func append(_ frame: SanitizedFrame) throws -> Bool {
        guard hasStarted else {
            throw EpisodeWriterError.cannotStart
        }
        guard input.isReadyForMoreMediaData else {
            return false
        }
        guard adaptor.append(frame.pixelBuffer, withPresentationTime: frame.presentationTime) else {
            throw writer.error ?? EpisodeWriterError.cannotAppend
        }
        return true
    }

    func finish(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard hasStarted else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            completion(.failure(EpisodeWriterError.noFrames))
            return
        }

        input.markAsFinished()
        writer.finishWriting { [self] in
            guard writer.status == .completed else {
                completion(.failure(writer.error ?? EpisodeWriterError.cannotFinish))
                return
            }

            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: outputURL.path
                )
                completion(.success(outputURL))
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                completion(.failure(error))
            }
        }
    }

    func cancel() {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
    }

    private static func makeOutputURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var directory = applicationSupport.appendingPathComponent(
            "SanitizedEpisodes",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)

        return directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
    }
}

private enum EpisodeWriterError: LocalizedError {
    case cannotAddInput
    case cannotStart
    case pixelBufferPoolUnavailable
    case cannotAllocatePixelBuffer(CVReturn)
    case cannotAppend
    case noFrames
    case cannotFinish

    var errorDescription: String? {
        switch self {
        case .cannotAddInput:
            "The sanitized video input could not be configured."
        case .cannotStart:
            "The sanitized video writer could not start."
        case .pixelBufferPoolUnavailable:
            "The sanitized output buffer pool is unavailable."
        case let .cannotAllocatePixelBuffer(status):
            "A sanitized output buffer could not be allocated (\(status))."
        case .cannotAppend:
            "A sanitized frame could not be written."
        case .noFrames:
            "No sanitized frames were recorded."
        case .cannotFinish:
            "The sanitized video could not be finalized."
        }
    }
}
