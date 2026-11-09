@preconcurrency import AVFoundation
import Foundation

struct CaptureResourceStatus: Equatable, Sendable {
    let thermalState: String
    let pressureState: String
    let targetFramesPerSecond: Int
}

final class ResourceGovernor {
    var onChange: (@Sendable (CaptureResourceStatus) -> Void)?

    private var thermalObserver: NSObjectProtocol?
    private var pressureObservation: NSKeyValueObservation?
    private let lock = NSLock()
    private var thermalState = ProcessInfo.processInfo.thermalState
    private var pressureLevel: AVCaptureDevice.SystemPressureState.Level = .nominal

    func startMonitoring(_ device: AVCaptureDevice) {
        if thermalObserver == nil {
            thermalObserver = NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.updateThermalState()
            }
        }

        pressureObservation = device.observe(
            \.systemPressureState,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let level = change.newValue?.level else { return }
            self?.updatePressureLevel(level)
        }
        publish()
    }

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
        pressureObservation?.invalidate()
    }

    private func updateThermalState() {
        lock.lock()
        thermalState = ProcessInfo.processInfo.thermalState
        lock.unlock()
        publish()
    }

    private func updatePressureLevel(
        _ level: AVCaptureDevice.SystemPressureState.Level
    ) {
        lock.lock()
        pressureLevel = level
        lock.unlock()
        publish()
    }

    private func publish() {
        lock.lock()
        let thermal = thermalState
        let pressure = pressureLevel
        lock.unlock()

        let thermalFPS: Int
        switch thermal {
        case .nominal, .fair:
            thermalFPS = 30
        case .serious:
            thermalFPS = 24
        case .critical:
            thermalFPS = 15
        @unknown default:
            thermalFPS = 15
        }

        let pressureFPS: Int
        switch pressure {
        case .nominal, .fair:
            pressureFPS = 30
        case .serious:
            pressureFPS = 24
        case .critical, .shutdown:
            pressureFPS = 15
        default:
            pressureFPS = 15
        }

        onChange?(
            CaptureResourceStatus(
                thermalState: Self.thermalName(thermal),
                pressureState: Self.pressureName(pressure),
                targetFramesPerSecond: min(thermalFPS, pressureFPS)
            )
        )
    }

    private static func thermalName(
        _ state: ProcessInfo.ThermalState
    ) -> String {
        switch state {
        case .nominal:
            "nominal"
        case .fair:
            "fair"
        case .serious:
            "serious"
        case .critical:
            "critical"
        default:
            "unknown"
        }
    }

    private static func pressureName(
        _ level: AVCaptureDevice.SystemPressureState.Level
    ) -> String {
        switch level {
        case .nominal:
            "nominal"
        case .fair:
            "fair"
        case .serious:
            "serious"
        case .critical:
            "critical"
        case .shutdown:
            "shutdown"
        default:
            "unknown"
        }
    }
}
