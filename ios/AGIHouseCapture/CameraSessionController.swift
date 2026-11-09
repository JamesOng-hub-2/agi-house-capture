@preconcurrency import AVFoundation
import CoreMedia
import Foundation

final class CameraSessionController: NSObject {
    let session = AVCaptureSession()

    var onStateChange: (@Sendable (CaptureState) -> Void)?
    var onDiagnostics: (@Sendable (CaptureDiagnostics) -> Void)?

    private let sessionQueue = DispatchQueue(label: "capture.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "capture.output", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "capture.frames", qos: .userInitiated)
    private let inFlightFrames = DispatchSemaphore(value: 2)
    private let diagnosticsLock = NSLock()

    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var diagnostics = CaptureDiagnostics()

    override init() {
        super.init()
        observeSessionEvents()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configureAndStart() {
        emit(.configuring)

        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }

                guard !self.session.isRunning else {
                    self.emit(.previewing)
                    return
                }

                self.session.startRunning()
                self.emit(self.session.isRunning ? .previewing : .failed("The camera did not start."))
            } catch {
                self.emit(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.emit(.idle)
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        try camera.lockForConfiguration()
        let frameDuration = CMTime(value: 1, timescale: 30)
        camera.activeVideoMinFrameDuration = frameDuration
        camera.activeVideoMaxFrameDuration = frameDuration
        camera.unlockForConfiguration()

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CameraError.cannotAddOutput
        }
        session.addOutput(videoOutput)
    }

    private func observeSessionEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        emit(.interrupted("Another activity is using the camera."))
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        configureAndStart()
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError

        if error?.code == AVError.Code.mediaServicesWereReset.rawValue {
            configureAndStart()
        } else {
            emit(.failed(error?.localizedDescription ?? "The camera session failed."))
        }
    }

    private func consume(_ sampleBuffer: CMSampleBuffer) {
        defer { inFlightFrames.signal() }

        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        var snapshot: CaptureDiagnostics?

        diagnosticsLock.lock()
        diagnostics.processedFrames += 1
        diagnostics.latestTimestampSeconds = timestamp.isFinite ? timestamp : nil
        if diagnostics.processedFrames.isMultiple(of: 30) {
            snapshot = diagnostics
        }
        diagnosticsLock.unlock()

        if let snapshot {
            emitDiagnostics(snapshot)
        }
    }

    private func recordDroppedFrame() {
        diagnosticsLock.lock()
        diagnostics.droppedFrames += 1
        let snapshot = diagnostics
        diagnosticsLock.unlock()
        emitDiagnostics(snapshot)
    }

    private func emit(_ state: CaptureState) {
        onStateChange?(state)
    }

    private func emitDiagnostics(_ diagnostics: CaptureDiagnostics) {
        onDiagnostics?(diagnostics)
    }
}

extension CameraSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard inFlightFrames.wait(timeout: .now()) == .success else {
            recordDroppedFrame()
            return
        }

        processingQueue.async { [self] in
            self.consume(sampleBuffer)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        recordDroppedFrame()
    }
}

private enum CameraError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "No rear camera is available."
        case .cannotAddInput:
            "The camera input could not be configured."
        case .cannotAddOutput:
            "The camera frame output could not be configured."
        }
    }
}
