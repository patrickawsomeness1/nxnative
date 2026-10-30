import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isImporting = false
    @State private var payloadReport: PayloadReport?
    @State private var inspectionError: String?

    var body: some View {
        ScrollView {
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

                Divider()

                Text("Homebrew payload inspector")
                    .font(.title2.bold())
                Text("Import a self-built NRO, NSO or ELF64 test program to inspect its container header and loadable segments. This does not execute the file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    isImporting = true
                } label: {
                    Label("Choose test program", systemImage: "doc.badge.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let inspectionError {
                    Text(inspectionError)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if let report = payloadReport {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(report.fileName).font(.headline).lineLimit(2)
                        infoRow("Format", report.format)
                        infoRow("Architecture", report.architecture)
                        infoRow("Version", report.version)
                        infoRow("File size", ByteCountFormatter.string(fromByteCount: Int64(report.fileSize), countStyle: .file))
                        infoRow("Build ID", report.buildID.isEmpty ? "Unavailable" : report.buildID)

                        Text("Loadable segments").font(.headline).padding(.top, 6)
                        ForEach(Array(report.segments.enumerated()), id: \.offset) { _, segment in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(segment.name).font(.system(.subheadline, design: .monospaced))
                                Text("file 0x\(String(segment.fileOffset, radix: 16)) · \(segment.fileSize) bytes   memory 0x\(String(segment.memoryOffset, radix: 16)) · \(segment.memorySize) bytes")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                            Text("• \(note)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                payloadReport = try PayloadParser.inspect(data, fileName: url.lastPathComponent)
                inspectionError = nil
            } catch {
                payloadReport = nil
                inspectionError = error.localizedDescription
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}
