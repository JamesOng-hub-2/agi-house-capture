import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("Ready to capture")
                    .font(.title2.bold())

                Text("Camera capture, on-device anonymization, and edge upload will live here.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("AGI House Capture")
        }
    }
}

#Preview {
    ContentView()
}
