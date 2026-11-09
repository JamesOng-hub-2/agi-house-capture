import AVFoundation
import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var diagnostics = CaptureDiagnostics()
    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var privacyDiagnostics = PrivacyDiagnostics()
    @Published private(set) var uploadState: UploadState = .idle

    let camera = CameraSessionController()
    private let uploadCoordinator = UploadCoordinator(
        baseURL: URL(string: "http://192.168.7.10:8000")!
    )
    private var isProcessingUploads = false

    init() {
        camera.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.state = state
            }
        }
        camera.onDiagnostics = { [weak self] diagnostics in
            Task { @MainActor [weak self] in
                self?.diagnostics = diagnostics
            }
        }
        camera.onRecordingStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.recordingState = state
                if case let .saved(url) = state {
                    self?.enqueueForUpload(url)
                }
            }
        }
        camera.onPrivacyDiagnostics = { [weak self] diagnostics in
            Task { @MainActor [weak self] in
                self?.privacyDiagnostics = diagnostics
            }
        }
    }

    func start() {
        resumeUploads()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera.configureAndStart()
        case .notDetermined:
            state = .requestingPermission
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    camera.configureAndStart()
                } else {
                    state = .denied
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .failed("Unknown camera authorization state.")
        }
    }

    func suspend() {
        camera.stop()
    }

    func toggleRecording() {
        if recordingState.isRecording {
            camera.stopRecording()
        } else if state == .previewing {
            camera.startRecording()
        }
    }

    func retryUploads() {
        Task {
            await processPendingUploads()
        }
    }

    private func enqueueForUpload(_ url: URL) {
        uploadState = .preparing
        Task {
            do {
                let count = try await uploadCoordinator.enqueue(
                    fileURL: url,
                    taskID: "pick-and-place"
                )
                uploadState = .queued(count, nil)
                await processPendingUploads()
            } catch {
                uploadState = .queued(
                    await uploadCoordinator.pendingCount(),
                    error.localizedDescription
                )
            }
        }
    }

    private func resumeUploads() {
        guard !isProcessingUploads else { return }
        Task {
            let count = await uploadCoordinator.pendingCount()
            guard count > 0 else { return }
            uploadState = .queued(count, nil)
            await processPendingUploads()
        }
    }

    private func processPendingUploads() async {
        guard !isProcessingUploads else { return }
        isProcessingUploads = true
        defer { isProcessingUploads = false }

        while await uploadCoordinator.pendingCount() > 0 {
            let count = await uploadCoordinator.pendingCount()
            uploadState = .uploading(count)

            do {
                guard let (result, remaining) = try await uploadCoordinator.uploadNext() else {
                    uploadState = .idle
                    return
                }
                uploadState = .completed(
                    decision: result.decision,
                    reason: result.reason
                )
                if remaining == 0 {
                    return
                }
            } catch {
                uploadState = .queued(
                    await uploadCoordinator.pendingCount(),
                    error.localizedDescription
                )
                return
            }
        }
    }
}
