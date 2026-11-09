import AVFoundation
import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var diagnostics = CaptureDiagnostics()

    let camera = CameraSessionController()

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
    }

    func start() {
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
}
