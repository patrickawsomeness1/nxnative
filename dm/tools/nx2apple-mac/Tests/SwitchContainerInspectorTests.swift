import XCTest
@testable import SwitchContainerInspector

final class SwitchContainerInspectorTests: XCTestCase {
    private func put32(_ value: UInt32, into bytes: inout [UInt8]) {
        for i in 0..<4 { bytes.append(UInt8((value >> (i * 8)) & 0xff)) }
    }
    private func put64(_ value: UInt64, into bytes: inout [UInt8]) {
        for i in 0..<8 { bytes.append(UInt8((value >> (i * 8)) & 0xff)) }
    }
    private func fixture(magic: String, entrySize: Int = 0x18, name: String = "test.nca", payload: [UInt8] = [1,2,3]) -> Data {
        var bytes = Array(magic.utf8)
        put32(1, into: &bytes)
        put32(UInt32(name.utf8.count + 1), into: &bytes)
        put32(0, into: &bytes)
        put64(0, into: &bytes)
        put64(UInt64(payload.count), into: &bytes)
        put32(0, into: &bytes)
        put32(0, into: &bytes)
        if entrySize == 0x40 { bytes += Array(repeating: 0, count: 0x40 - 0x18) }
        bytes += Array(name.utf8) + [0]
        bytes += payload
        return Data(bytes)
    }

    func testParsesPFS0DirectoryAndEntryBounds() throws {
        let result = try SwitchContainerInspector.inspect(fixture(magic: "PFS0"))
        XCTAssertEqual(result.format, "PFS0")
        XCTAssertEqual(result.entries, [SwitchContainerEntry(name: "test.nca", offset: 0x29, size: 3)])
    }

    func testParsesHFS0Directory() throws {
        let result = try SwitchContainerInspector.inspect(fixture(magic: "HFS0", entrySize: 0x40))
        XCTAssertEqual(result.format, "HFS0")
        XCTAssertEqual(result.entries.first?.name, "test.nca")
    }

    func testRejectsTruncatedHeader() {
        XCTAssertThrowsError(try SwitchContainerInspector.inspect(Data([0x50,0x46,0x53])))
    }

    func testRejectsUnknownMagic() {
        XCTAssertThrowsError(try SwitchContainerInspector.inspect(Data(repeating: 0, count: 64)))
    }

    func testRejectsOutOfRangeEntry() {
        var bytes = Array(fixture(magic: "PFS0"))
        // First entry's data size is at header + 8; set it beyond EOF.
        let sizeOffset = 0x10 + 8
        for i in 0..<8 { bytes[sizeOffset + i] = 0xff }
        XCTAssertThrowsError(try SwitchContainerInspector.inspect(Data(bytes)))
    }

    func testRejectsPathTraversalName() {
        let data = fixture(magic: "PFS0", name: "../unsafe")
        XCTAssertThrowsError(try SwitchContainerInspector.inspect(data))
    }

    func testRejectsExcessiveEntryCount() {
        var bytes = Array("PFS0".utf8) + [0,0,0,0,0,0,0,0] + Array(repeating: 0, count: 4)
        bytes[4] = 0xff; bytes[5] = 0xff; bytes[6] = 0xff; bytes[7] = 0x7f
        XCTAssertThrowsError(try SwitchContainerInspector.inspect(Data(bytes)))
    }
}
