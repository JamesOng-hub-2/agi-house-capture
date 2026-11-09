import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = CaptureViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: viewModel.camera.session)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                statusHeader
                Spacer()
                recordingStatus
                savedEpisodeAction
                recordButton
                diagnosticsPanel
                uploadPanel
            }
            .padding()
        }
        .task { viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.start()
            case .inactive, .background:
                viewModel.suspend()
            @unknown default:
                viewModel.suspend()
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.state.symbolName)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.state.title)
                    .font(.headline)

                if let detail = viewModel.state.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if viewModel.state == .denied {
                Button("Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Phase 2 · Sanitized recording")
                .font(.headline)

            HStack {
                metric("Sanitized", value: viewModel.privacyDiagnostics.sanitizedFrames)
                Divider().frame(height: 32)
                metric("Faces", value: viewModel.privacyDiagnostics.detectedFaces)
                Divider().frame(height: 32)
                metric("Fallbacks", value: viewModel.privacyDiagnostics.fullFrameFallbacks)
            }

            HStack {
                Text(
                    "720p · \(viewModel.resourceStatus.targetFramesPerSecond) fps · no audio"
                )
                Spacer()
                Text("Dropped \(viewModel.diagnostics.droppedFrames)")
            }
            .font(.caption.monospaced())

            Text(
                "Thermal \(viewModel.resourceStatus.thermalState) · pressure \(viewModel.resourceStatus.pressureState)"
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)

            Text("The preview is raw. Saved MP4 files contain only separately rendered sanitized frames.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingStatus: some View {
        Text(recordingStatusText)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
    }

    @ViewBuilder
    private var savedEpisodeAction: some View {
        if case let .saved(url) = viewModel.recordingState,
           FileManager.default.fileExists(atPath: url.path) {
            ShareLink(item: url) {
                Label("Inspect sanitized video", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var uploadPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: uploadSymbol)
                .foregroundStyle(uploadColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.uploadState.title)
                    .font(.subheadline.weight(.semibold))
                if let detail = viewModel.uploadState.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if case .queued = viewModel.uploadState {
                Button("Retry") {
                    viewModel.retryUploads()
                }
                .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var recordButton: some View {
        Button {
            viewModel.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 76, height: 76)
                if viewModel.recordingState.isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 62, height: 62)
                }
            }
        }
        .disabled(
            viewModel.state != .previewing ||
            viewModel.recordingState == .finalizing
        )
        .opacity(viewModel.state == .previewing ? 1 : 0.5)
        .accessibilityLabel(viewModel.recordingState.isRecording ? "Stop recording" : "Start recording")
    }

    private var recordingStatusText: String {
        switch viewModel.recordingState {
        case .idle:
            "Ready to record"
        case .starting:
            "Starting privacy pipeline"
        case .recording:
            "Recording sanitized frames"
        case .finalizing:
            "Validating sanitized video"
        case let .saved(url):
            "Saved \(url.lastPathComponent)"
        case let .failed(message):
            "Recording failed: \(message)"
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .previewing:
            .green
        case .denied, .failed:
            .red
        case .interrupted:
            .orange
        default:
            .white
        }
    }

    private var uploadSymbol: String {
        switch viewModel.uploadState {
        case .idle:
            "tray"
        case .preparing:
            "gearshape"
        case .queued:
            "clock.arrow.circlepath"
        case .uploading:
            "arrow.up.circle.fill"
        case let .completed(decision, _):
            decision == "accepted" ? "checkmark.circle.fill" : "checkmark.circle"
        }
    }

    private var uploadColor: Color {
        switch viewModel.uploadState {
        case .queued:
            .orange
        case .uploading:
            .blue
        case let .completed(decision, _):
            decision == "rejected" ? .red : .green
        default:
            .white
        }
    }
}

#Preview {
    ContentView()
}
