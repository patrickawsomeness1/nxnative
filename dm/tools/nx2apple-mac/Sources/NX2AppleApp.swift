import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

@main
struct NX2AppleApp: App {
    var body: some Scene {
        WindowGroup { DashboardView() }
            .windowStyle(.titleBar)
            .defaultSize(width: 820, height: 680)
    }
}

@MainActor
final class BuildController: ObservableObject {
    @Published var repository = ""
    @Published var selectedGame = ""
    @Published var deviceID = ""
    @Published var teamID = ""
    @Published var log = "Choose your nxnative repository folder to get started."
    @Published var busy = false
    @Published var gameAssessment = "No game selected"
    @Published var packageAssessment = "No HBLauncher package selected"
    @Published var ipaPath = ""

    private func run(_ executable: String, _ arguments: [String], cwd: URL? = nil) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let cwd { process.currentDirectoryURL = cwd }
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "NX2Apple", code: Int(process.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "Command failed: \(executable)" : text])
            }
            return text
        }.value
    }

    func chooseRepository(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        repository = url.path
        log = "Repository: \(url.path)\nChecking required project files…"
        let iosSpec = url.appending(path: "dm/tests/switch2/ios/Project.yml")
        let tool = url.appending(path: "dm/tools/patch_nso.py")
        if FileManager.default.fileExists(atPath: iosSpec.path),
           FileManager.default.fileExists(atPath: tool.path) {
            log += "\nRepository structure looks valid."
        } else {
            log += "\nMissing expected nxnative files. Select the repository root."
        }
    }

    func chooseGame(_ url: URL) {
        selectedGame = url.path
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "nso", "nro", "elf":
            gameAssessment = "Recognized homebrew/container candidate. nxnative can inspect some metadata, but the Switch 2 execution loader is not implemented; this file cannot currently be turned into a playable IPA."
        case "nsp", "xci":
            gameAssessment = "Retail package selected. Retail package decryption, key handling, content installation, and Switch 2 execution are not implemented. This app will not attempt to bypass encryption or DRM."
        default:
            gameAssessment = "File selected, but this format is not currently supported by the Switch 2 survey tools."
        }
    }

    func chooseHBXPackage(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        selectedGame = url.path
        let manifestURL = url.appending(path: "manifest.json")
        let buildURL = url.appending(path: "build")
        let reportURL = buildURL.appending(path: "report.json")
        let codeURL = buildURL.appending(path: "code.bin")
        let dataURL = buildURL.appending(path: "data.bin")
        do {
            let manifestData = try Data(contentsOf: manifestURL)
            let reportData = try Data(contentsOf: reportURL)
            guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                  let report = try JSONSerialization.jsonObject(with: reportData) as? [String: Any] else {
                throw NSError(domain: "NX2Apple", code: 10, userInfo: [NSLocalizedDescriptionKey: "Package manifest or build report is not valid JSON."])
            }
            guard (report["format"] as? String) == "hblauncher-native-app/1",
                  (report["abi"] as? Int) == 3,
                  (manifest["abi"] as? Int) == 3,
                  (manifest["id"] as? String) == (report["id"] as? String),
                  (manifest["kind"] as? String) == "native",
                  (report["kind"] as? String) == "native" else {
                throw NSError(domain: "NX2Apple", code: 11, userInfo: [NSLocalizedDescriptionKey: "This is not a matching HBLauncher Native ABI 3 package."])
            }
            let code = try Data(contentsOf: codeURL, options: .mappedIfSafe)
            let data = try Data(contentsOf: dataURL, options: .mappedIfSafe)
            let codeHash = SHA256.hash(data: code).map { String(format: "%02x", $0) }.joined()
            let dataHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard code.count == (report["codeBytes"] as? Int),
                  data.count == (report["dataBytes"] as? Int),
                  codeHash == (report["codeSha256"] as? String),
                  dataHash == (report["dataSha256"] as? String) else {
                throw NSError(domain: "NX2Apple", code: 12, userInfo: [NSLocalizedDescriptionKey: "The code/data files do not match the SDK build report. Rebuild the package before importing it."])
            }
            let codeBase = report["codeBase"] as? String ?? "unknown"
            let dataBase = report["dataBase"] as? String ?? "unknown"
            packageAssessment = "Verified HBLauncher ABI 3 package: \\(report["id"] as? String ?? "unnamed"). Code/data sizes and SHA-256 hashes match. Fixed bases: \\(codeBase) / \\(dataBase). This validates package integrity only; the Switch 2 runtime and Apple execution bridge are not yet implemented."
            gameAssessment = packageAssessment
            log = "Imported HBLauncher package: \\(url.path)\\n\\(packageAssessment)"
        } catch {
            packageAssessment = "Package validation failed: \\(error.localizedDescription)"
            gameAssessment = packageAssessment
            log = packageAssessment
        }
    }

    func buildDiagnosticIPA() async {
        guard !repository.isEmpty else { log = "Select the nxnative repository folder first."; return }
        guard !teamID.trimmingCharacters(in: .whitespaces).isEmpty else { log = "Enter your Apple Developer Team ID before requesting a signed IPA."; return }
        let root = URL(fileURLWithPath: repository)
        guard FileManager.default.fileExists(atPath: root.appending(path: "dm/tests/switch2/ios/Project.yml").path) else {
            log = "The selected folder is not the nxnative repository root."; return
        }
        busy = true
        defer { busy = false }
        log = "Generating the iOS project…"
        do {
            _ = try await run("/usr/bin/env", ["xcodegen", "generate", "--spec", "dm/tests/switch2/ios/Project.yml", "--project", "dm/tests/switch2/ios"], cwd: root)
            log += "\nArchiving the Switch 2 hardware diagnostic app…"
            let build = root.appending(path: "build/NX2Apple")
            try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
            let archive = build.appending(path: "Switch2Bringup.xcarchive")
            _ = try await run("/usr/bin/xcodebuild", [
                "-project", "dm/tests/switch2/ios/Switch2Bringup.xcodeproj",
                "-scheme", "Switch2Bringup", "-configuration", "Release",
                "-destination", "generic/platform=iOS",
                "-archivePath", archive.path, "-allowProvisioningUpdates", "DEVELOPMENT_TEAM=\(teamID)", "archive"
            ], cwd: root)
            log += "\nExporting signed development IPA (requires Xcode signing account and provisioning)…"
            let options = build.appending(path: "ExportOptions.plist")
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>method</key><string>development</string>
              <key>signingStyle</key><string>automatic</string>
              <key>teamID</key><string>\(teamID)</string>
              <key>destination</key><string>export</string>
            </dict></plist>
            """
            try plist.write(to: options, atomically: true, encoding: .utf8)
            _ = try await run("/usr/bin/xcodebuild", [
                "-exportArchive", "-archivePath", archive.path,
                "-exportPath", build.appending(path: "export").path,
                "-exportOptionsPlist", options.path, "-allowProvisioningUpdates"
            ], cwd: root)
            let ipa = build.appending(path: "export/Switch2Bringup.ipa")
            guard FileManager.default.fileExists(atPath: ipa.path) else {
                throw NSError(domain: "NX2Apple", code: 2, userInfo: [NSLocalizedDescriptionKey: "Xcode completed but the expected IPA was not found in build/NX2Apple/export."])
            }
            ipaPath = ipa.path
            log += "\nSUCCESS: signed diagnostic IPA exported at \(ipa.path)\nThis is a Metal/PAC/XOM hardware test app, not a game IPA."
        } catch {
            log += "\nBUILD FAILED: \(error.localizedDescription)"
        }
    }

    func listDevices() async {
        busy = true
        defer { busy = false }
        do {
            log = try await run("/usr/bin/xcrun", ["devicectl", "list", "devices"])
        } catch { log = "Could not list devices. Connect an unlocked iPhone/iPad, trust this Mac, and check Xcode pairing.\n\(error.localizedDescription)" }
    }

    func installIPA() async {
        guard !deviceID.trimmingCharacters(in: .whitespaces).isEmpty,
              !ipaPath.isEmpty else {
            log = "Build the signed diagnostic IPA and enter the connected device identifier first."; return
        }
        busy = true
        defer { busy = false }
        do {
            let app = URL(fileURLWithPath: repository)
                .appending(path: "build/NX2Apple/Switch2Bringup.xcarchive/Products/Applications/Switch2Bringup.app")
            guard FileManager.default.fileExists(atPath: app.path) else {
                throw NSError(domain: "NX2Apple", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "The archived diagnostic app was not found. Build and export the signed diagnostic IPA first."
                ])
            }
            log = "Verifying the archived app signature…"
            _ = try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", app.path])
            log += "\nInstalling the verified diagnostic app…"
            log += try await run("/usr/bin/xcrun", [
                "devicectl", "device", "install", "app",
                "--device", deviceID.trimmingCharacters(in: .whitespaces),
                app.path
            ])
            log += "\nInstall command completed successfully."
        } catch { log += "\nInstall failed: \(error.localizedDescription)" }
    }
}

struct DashboardView: View {
    @StateObject private var controller = BuildController()
    @State private var showRepoPicker = false
    @State private var showGamePicker = false
    @State private var showPackagePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NX2Apple").font(.system(size: 30, weight: .bold))
                    Text("Switch 2 → Apple device build manager").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "gamecontroller.fill").font(.system(size: 32)).foregroundStyle(.cyan)
            }
            Divider()
            GroupBox("1 · Project") {
                HStack {
                    Text(controller.repository.isEmpty ? "No nxnative repository selected" : controller.repository)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose folder…") { showRepoPicker = true }
                }.padding(6)
            }
            GroupBox("2 · Select homebrew / game file") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(controller.selectedGame.isEmpty ? "No file selected" : URL(fileURLWithPath: controller.selectedGame).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Button("Select file…") { showGamePicker = true }
                    }
                    Text(controller.gameAssessment).font(.callout).foregroundStyle(.secondary)
                }.padding(6)
            }
            GroupBox("3 · Import native homebrew package") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(controller.selectedGame.isEmpty ? "No package folder selected" : controller.selectedGame)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose package folder…") { showPackagePicker = true }
                    }
                    Text(controller.packageAssessment).font(.callout).foregroundStyle(.secondary)
                }.padding(6)
            }
            GroupBox("3 · Build and install") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button {
                            Task { await controller.buildDiagnosticIPA() }
                        } label: { Label("Build signed diagnostic IPA", systemImage: "hammer.fill") }
                        .disabled(controller.busy || controller.repository.isEmpty)
                        Button {
                            Task { await controller.listDevices() }
                        } label: { Label("Find devices", systemImage: "iphone.gen3") }
                        .disabled(controller.busy)
                    }
                    HStack {
                        TextField("Apple Developer Team ID", text: $controller.teamID)
                            .textFieldStyle(.roundedBorder)
                        TextField("Connected device UDID", text: $controller.deviceID)
                            .textFieldStyle(.roundedBorder)
                        Button("Install diagnostic app") {
                            Task { await controller.installIPA() }
                        }.disabled(controller.busy || controller.ipaPath.isEmpty)
                    }
                    Text("The current build target is the hardware diagnostic app. Selecting a game does not yet create a playable game IPA: the Switch 2 native loader, Horizon runtime, and NVN2-to-Metal renderer are still unfinished.")
                        .font(.caption).foregroundStyle(.orange)
                }.padding(6)
            }
            GroupBox("Build log") {
                ScrollView {
                    Text(controller.log).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(minHeight: 170)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .fileImporter(isPresented: $showRepoPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { controller.chooseRepository(url) }
        }
        .fileImporter(isPresented: $showGamePicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { controller.chooseGame(url) }
        }
        .fileImporter(isPresented: $showPackagePicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { controller.chooseHBXPackage(url) }
        }
    }
}
