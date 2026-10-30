import SwiftUI

@main
struct Switch2BringupApp: App {
    var body: some Scene {
        WindowGroup {
            BringupDashboard()
                .preferredColorScheme(.dark)
        }
    }
}

struct BringupDashboard: View {
    @StateObject private var renderer = MetalSmokeRenderer()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Switch 2 · Metal Bring-up")
                .font(.largeTitle.bold())

            Text("Stage 0: Apple GPU validation")
                .font(.headline)
                .foregroundStyle(.secondary)

            MetalSmokeView(renderer: renderer)
                .frame(minHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Group {
                infoRow("Metal device", renderer.deviceName)
                infoRow("GPU", renderer.gpuStatus)
                infoRow("Frames submitted", String(renderer.frameCount))
                infoRow("Max buffer", renderer.maxBufferLength)
                infoRow("Recommended working set", renderer.workingSet)
            }
            .font(.system(.body, design: .monospaced))

            Text(renderer.message)
                .font(.footnote)
                .foregroundStyle(renderer.deviceAvailable ? .green : .orange)

            Spacer(minLength: 0)
        }
        .padding()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
