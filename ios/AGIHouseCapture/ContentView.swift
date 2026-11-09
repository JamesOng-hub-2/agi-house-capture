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
                diagnosticsPanel
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
            Text("Phase 1 · Raw preview only")
                .font(.headline)

            HStack {
                metric("Processed", value: viewModel.diagnostics.processedFrames)
                Divider().frame(height: 32)
                metric("Dropped", value: viewModel.diagnostics.droppedFrames)
                Spacer()
                Text("720p · 30 fps")
                    .font(.caption.monospaced())
            }

            Text("Frames are held briefly in bounded memory and are not saved or uploaded.")
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
}

#Preview {
    ContentView()
}
