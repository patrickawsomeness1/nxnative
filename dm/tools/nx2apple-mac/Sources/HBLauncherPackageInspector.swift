import Foundation
import CryptoKit

struct HBLauncherPackageSummary: Equatable {
    let identifier: String
    let codeBase: UInt64
    let dataBase: UInt64
    let entry: UInt64
    let codeBytes: Int
    let dataBytes: Int
    let dataRegionBytes: Int
    let codeSHA256: String
    let dataSHA256: String
}

enum HBLauncherPackageError: Error, LocalizedError {
    case invalidJSON
    case incompatibleABI
    case invalidIdentity
    case invalidImageHashes
    case invalidImageSizes
    case invalidAddressMetadata
    case overlappingRegions
    case invalidRegionSize

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Package manifest or build report is not valid JSON."
        case .incompatibleABI: return "This is not a matching HBLauncher Native ABI 3 package."
        case .invalidIdentity: return "The package identifier is missing or does not match."
        case .invalidImageHashes: return "The code/data files do not match the SDK build report."
        case .invalidImageSizes: return "The code/data byte counts do not match the SDK build report."
        case .invalidAddressMetadata: return "The build report has invalid or unaligned fixed-address metadata."
        case .overlappingRegions: return "The package code and data memory regions overlap or overflow."
        case .invalidRegionSize: return "The package declares an invalid or undersized memory region."
        }
    }
}

/// Integrity and address-range validation only. This does not map or execute guest code.
enum HBLauncherPackageInspector {
    static func inspect(manifestData: Data, reportData: Data, code: Data, data: Data) throws -> HBLauncherPackageSummary {
        guard let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let report = try? JSONSerialization.jsonObject(with: reportData) as? [String: Any] else {
            throw HBLauncherPackageError.invalidJSON
        }
        guard (report["format"] as? String) == "hblauncher-native-app/1",
              (report["abi"] as? Int) == 3,
              (manifest["abi"] as? Int) == 3,
              (manifest["kind"] as? String) == "native",
              (report["kind"] as? String) == "native" else {
            throw HBLauncherPackageError.incompatibleABI
        }
        guard let manifestID = manifest["id"] as? String, !manifestID.isEmpty,
              let reportID = report["id"] as? String, !reportID.isEmpty,
              manifestID == reportID else {
            throw HBLauncherPackageError.invalidIdentity
        }
        guard let codeBytes = report["codeBytes"] as? Int,
              let dataBytes = report["dataBytes"] as? Int,
              codeBytes > 0, dataBytes >= 0,
              code.count == codeBytes, data.count == dataBytes else {
            throw HBLauncherPackageError.invalidImageSizes
        }
        let codeHash = SHA256.hash(data: code).map { String(format: "%02x", $0) }.joined()
        let dataHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard codeHash == (report["codeSha256"] as? String),
              dataHash == (report["dataSha256"] as? String) else {
            throw HBLauncherPackageError.invalidImageHashes
        }
        guard let codeBaseText = report["codeBase"] as? String,
              let dataBaseText = report["dataBase"] as? String,
              let entryText = report["entry"] as? String,
              let dataRegionBytes = report["dataRegionBytes"] as? Int,
              let codePages = report["codePages"] as? Int,
              dataRegionBytes >= dataBytes, dataRegionBytes > 0 else {
            throw HBLauncherPackageError.invalidRegionSize
        }
        func address(_ value: String) -> UInt64? {
            let digits = value.lowercased().hasPrefix("0x") ? String(value.dropFirst(2)) : value
            return UInt64(digits, radix: 16)
        }
        guard let codeBase = address(codeBaseText), let dataBase = address(dataBaseText),
              let entry = address(entryText), codeBase > 0, dataBase > 0,
              codeBase % 0x1000 == 0, dataBase % 0x1000 == 0,
              entry == codeBase,
              codePages == (codeBytes / 0x1000 + (codeBytes % 0x1000 == 0 ? 0 : 1)) else {
            throw HBLauncherPackageError.invalidAddressMetadata
        }
        let codeEnd = UInt64(codeBytes).addingReportingOverflow(codeBase)
        let dataEnd = UInt64(dataRegionBytes).addingReportingOverflow(dataBase)
        guard !codeEnd.overflow, !dataEnd.overflow,
              codeEnd.partialValue <= dataBase || dataEnd.partialValue <= codeBase else {
            throw HBLauncherPackageError.overlappingRegions
        }
        return HBLauncherPackageSummary(
            identifier: reportID, codeBase: codeBase, dataBase: dataBase, entry: entry,
            codeBytes: codeBytes, dataBytes: dataBytes, dataRegionBytes: dataRegionBytes,
            codeSHA256: codeHash, dataSHA256: dataHash
        )
    }
}
