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
    private var scopedRepositoryURL: URL?

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
        if let previous = scopedRepositoryURL { previous.stopAccessingSecurityScopedResource() }
        if url.startAccessingSecurityScopedResource() { scopedRepositoryURL = url }
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
        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
        selectedGame = url.path
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent.lowercased()
        let parts = fileName.split(separator: ".")
        let isSplitPackagePart = parts.count >= 2 &&
            ["nsp", "xci"].contains(String(parts[parts.count - 2])) &&
            (2...3).contains(parts.last?.count ?? 0) &&
            (parts.last?.allSatisfy { $0.isNumber } ?? false)

        var magic = ""
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let bytes = (try? handle.read(upToCount: 0x204)) ?? Data()
            if bytes.count >= 4 {
                magic = String(bytes: bytes.prefix(4), encoding: .ascii) ?? ""
            }
            if bytes.count >= 0x104 {
                let xci = String(bytes: bytes[0x100..<0x104], encoding: .ascii) ?? ""
                if xci == "HEAD" { magic = "XCIHEAD" }
            }
            if bytes.count >= 0x204 {
                let nca = String(bytes: bytes[0x200..<0x204], encoding: .ascii) ?? ""
                if nca == "NCA2" || nca == "NCA3" { magic = nca }
            }
        }

        let signatures: [String: String] = [
            "PFS0": "PFS0 container (NSP-family)",
            "HFS0": "HFS0 container (XCI-family)",
            "NSO0": "NSO executable module",
            "NRO0": "NRO homebrew executable",
            "KIP1": "KIP1 Horizon module",
            "XCIHEAD": "XCI game-card image",
            "NCA2": "NCA2 content archive",
            "NCA3": "NCA3 content archive",
            "\u{7f}ELF": "ELF executable/object"
        ]
        let formats: [String: String] = [
            "nsp": "NSP package; parsing, installation, and execution are not implemented.",
            "xci": "XCI game-card image; secure-partition processing and execution are not implemented.",
            "nsz": "Compressed NSP-family package; decompression and parsing are not implemented.",
            "xcz": "Compressed XCI-family image; decompression and parsing are not implemented.",
            "nca": "NCA content archive; encrypted-content processing and loading are not implemented.",
            "ncz": "Compressed NCA payload; decompression and NCA processing are not implemented.",
            "nro": "NRO homebrew executable; a verified Switch 2 loader/runtime is not implemented.",
            "nso": "NSO module; the Switch 1 patcher is not a Switch 2 loader.",
            "elf": "ELF executable/object; architecture, ABI, and relocations need validation.",
            "kip": "KIP module; Switch 2 compatibility is not established.",
            "kip1": "KIP1 module; Switch 2 compatibility is not established.",
            "nacp": "NACP application metadata; not a standalone executable.",
            "tik": "Ticket metadata; no ticket bypass or protected-content decryption is performed.",
            "cert": "Certificate data; not a game executable.",
            "cnmt": "CNMT content metadata; referenced content still needs package processing.",
            "romfs": "RomFS filesystem data; not a standalone executable.",
            "nax": "NAX encrypted data; key handling and decryption are not implemented.",
            "pfs0": "PFS0 filesystem/container; entry parsing is not implemented.",
            "hfs0": "HFS0 filesystem/container; entry parsing is not implemented.",
            "npdm": "NPDM process metadata; not a standalone executable."
        ]

        if let detected = signatures[magic] {
            if magic == "PFS0" || magic == "HFS0" {
                do {
                    let container = try Data(contentsOf: url, options: .mappedIfSafe)
                    let summary = try SwitchContainerInspector.inspect(container)
                    let names = summary.entries.prefix(12).map { "\($0.name) (\($0.size) bytes)" }.joined(separator: "\n")
                    let remaining = max(0, summary.entries.count - 12)
                    gameAssessment = "\(detected): parsed \(summary.entries.count) directory entries.\n\(names)\n\(remaining > 0 ? "... and \(remaining) more" : "")\nRead-only metadata inspection; extraction, decryption, installation, and execution are not implemented."
                } catch {
                    gameAssessment = "\(detected), but directory parsing failed: \(error.localizedDescription)"
                }
            } else {
                gameAssessment = "File signature: \(detected). Full parsing/loading is not yet implemented."
            }
        } else if let description = formats[ext] {
            gameAssessment = description
        } else if isSplitPackagePart {
            gameAssessment = "Split NSP/XCI part recognized by filename. All parts are required; assembly and validation are not implemented."
        } else {
            gameAssessment = "Unknown format. No supported signature or extension was detected; no execution is attempted."
        }
        log = "Selected: \(url.path)\n\(gameAssessment)"
    }

    func chooseHBXPackage(_ url: URL) {
        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
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
            guard let codeBaseText = report["codeBase"] as? String,
                  let dataBaseText = report["dataBase"] as? String,
                  let entryText = report["entry"] as? String,
                  let dataRegionBytes = report["dataRegionBytes"] as? Int,
                  let codePages = report["codePages"] as? Int,
                  dataRegionBytes >= data.count,
                  codePages == (code.count + 0xFFF) / 0x1000 else {
                throw NSError(domain: "NX2Apple", code: 13, userInfo: [NSLocalizedDescriptionKey: "The build report is missing valid address/region metadata."])
            }
            func parseAddress(_ value: String) -> UInt64? {
                let digits = value.lowercased().hasPrefix("0x") ? String(value.dropFirst(2)) : value
                return UInt64(digits, radix: 16)
            }
            guard let codeBase = parseAddress(codeBaseText),
                  let dataBase = parseAddress(dataBaseText),
                  let entry = parseAddress(entryText),
                  codeBase % 0x1000 == 0, dataBase % 0x1000 == 0,
                  entry == codeBase else {
                throw NSError(domain: "NX2Apple", code: 14, userInfo: [NSLocalizedDescriptionKey: "The package has invalid or unaligned fixed-address metadata."])
            }
            let codeRange = UInt64(code.count).addingReportingOverflow(codeBase)
            let dataRange = UInt64(dataRegionBytes).addingReportingOverflow(dataBase)
            guard !codeRange.overflow, !dataRange.overflow,
                  codeRange.partialValue <= dataBase || dataRange.partialValue <= codeBase else {
                throw NSError(domain: "NX2Apple", code: 15, userInfo: [NSLocalizedDescriptionKey: "The package code and data memory regions overlap or overflow."])
            }
            packageAssessment = "Verified HBLauncher ABI 3 package: \(report["id"] as? String ?? "unnamed"). Hashes, sizes, entry point, alignment, and memory regions match the report. Fixed bases: \(codeBaseText) / \(dataBaseText). Integrity validation only; Apple runtime is not implemented."
            gameAssessment = packageAssessment
            log = "Imported HBLauncher package: \(url.path)\n\(packageAssessment)"
        } catch {
            packageAssessment = "Package validation failed: \(error.localizedDescription)"
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
            GroupBox("4 · Build and install") {
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
