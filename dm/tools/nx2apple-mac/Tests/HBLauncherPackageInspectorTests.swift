import XCTest
import CryptoKit
@testable import SwitchContainerInspector

final class HBLauncherPackageInspectorTests: XCTestCase {
    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fixture(code: Data = Data(repeating: 0xA5, count: 0x1001),
                         data: Data = Data([1, 2, 3]),
                         codeBase: String = "0x0c000000",
                         dataBase: String = "0x0d000000",
                         entry: String = "0x0c000000",
                         dataRegionBytes: Int = 0x1000,
                         codePages: Int = 2,
                         identifier: String = "org.nxnative.probe") -> (Data, Data, Data, Data) {
        let manifest: [String: Any] = ["abi": 3, "kind": "native", "id": identifier]
        let report: [String: Any] = [
            "format": "hblauncher-native-app/1", "abi": 3, "kind": "native", "id": identifier,
            "codeBytes": code.count, "dataBytes": data.count,
            "codeSha256": hash(code), "dataSha256": hash(data),
            "codeBase": codeBase, "dataBase": dataBase, "entry": entry,
            "dataRegionBytes": dataRegionBytes, "codePages": codePages
        ]
        return (
            try! JSONSerialization.data(withJSONObject: manifest),
            try! JSONSerialization.data(withJSONObject: report), code, data
        )
    }

    private func inspect(_ f: (Data, Data, Data, Data)) throws -> HBLauncherPackageSummary {
        try HBLauncherPackageInspector.inspect(manifestData: f.0, reportData: f.1, code: f.2, data: f.3)
    }

    func testAcceptsMatchingABI3PackageAndReturnsValidatedSummary() throws {
        let result = try inspect(fixture())
        XCTAssertEqual(result.identifier, "org.nxnative.probe")
        XCTAssertEqual(result.codeBase, 0x0c000000)
        XCTAssertEqual(result.dataBase, 0x0d000000)
        XCTAssertEqual(result.entry, result.codeBase)
        XCTAssertEqual(result.codePages, nil)
        XCTAssertEqual(result.codeBytes, 0x1001)
    }

    func testRejectsMismatchedPackageIdentity() {
        let f = fixture(identifier: "org.other")
        let manifest = try! JSONSerialization.data(withJSONObject: ["abi": 3, "kind": "native", "id": "org.nxnative.probe"])
        XCTAssertThrowsError(try inspect((manifest, f.1, f.2, f.3))) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .invalidIdentity)
        }
    }

    func testRejectsWrongABI() {
        var f = fixture()
        f.0 = try! JSONSerialization.data(withJSONObject: ["abi": 2, "kind": "native", "id": "org.nxnative.probe"])
        XCTAssertThrowsError(try inspect(f)) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .incompatibleABI)
        }
    }

    func testRejectsModifiedCodeBytes() {
        let f = fixture()
        XCTAssertThrowsError(try inspect((f.0, f.1, Data([0]), f.3))) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .invalidImageSizes)
        }
    }

    func testRejectsModifiedCodeHash() {
        let f = fixture()
        XCTAssertThrowsError(try inspect((f.0, f.1, Data(repeating: 0, count: f.2.count), f.3))) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .invalidImageHashes)
        }
    }

    func testRejectsUnalignedFixedAddress() {
        let f = fixture(codeBase: "0x0c000001", entry: "0x0c000001")
        XCTAssertThrowsError(try inspect(f)) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .invalidAddressMetadata)
        }
    }

    func testRejectsEntryOutsideCodeBase() {
        let f = fixture(entry: "0x0c000100")
        XCTAssertThrowsError(try inspect(f)) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .invalidAddressMetadata)
        }
    }

    func testRejectsOverlappingRegions() {
        let f = fixture(dataBase: "0x0c001000")
        XCTAssertThrowsError(try inspect(f)) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .overlappingRegions)
        }
    }

    func testRejectsAddressOverflow() {
        let f = fixture(codeBase: "0xfffffffffffff000", dataBase: "0x0d000000", entry: "0xfffffffffffff000")
        XCTAssertThrowsError(try inspect(f)) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .overlappingRegions)
        }
    }

    func testRejectsUndersizedDataRegion() {
        let f = fixture(dataRegionBytes: 2)
        XCTAssertThrowsError(try inspect(f)) {
            XCTAssertEqual($0 as? HBLauncherPackageError, .invalidRegionSize)
        }
    }
}
