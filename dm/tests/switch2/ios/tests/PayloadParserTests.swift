import Foundation

@main
struct PayloadParserTests {
    static func main() throws {
        try testNRO()
        try testNSO()
        try testShortNSO()
        try testELF64()
        try testMalformedNRO()
        try testUnknown()
        print("PayloadParser: 5 tests passed")
    }

    static func testNRO() throws {
        var data = Data(repeating: 0, count: 0x200)
        putASCII("NRO0", in: &data, at: 0x10)
        put32(0, in: &data, at: 0x14)
        put32(UInt32(data.count), in: &data, at: 0x18)
        put32(0x100, in: &data, at: 0x20); put32(0x20, in: &data, at: 0x24)
        put32(0x120, in: &data, at: 0x28); put32(0x10, in: &data, at: 0x2c)
        put32(0x130, in: &data, at: 0x30); put32(0x10, in: &data, at: 0x34)
        put32(0x40, in: &data, at: 0x38)
        let report = try PayloadParser.inspect(data, fileName: "hello.nro")
        try expect(report.format == "Nintendo NRO0", "NRO format")
        try expect(report.architecture == "AArch64 (64-bit)", "NRO architecture")
        try expect(report.segments.count == 4, "NRO segment count including BSS")
    }

    static func testNSO() throws {
        var data = Data(repeating: 0, count: 0x100)
        putASCII("NSO0", in: &data, at: 0)
        put32(1, in: &data, at: 4)
        put32(0, in: &data, at: 0x0c)
        put32(0x70, in: &data, at: 0x10); put32(0x8000, in: &data, at: 0x14); put32(0x10, in: &data, at: 0x18)
        put32(0x80, in: &data, at: 0x20); put32(0x9000, in: &data, at: 0x24); put32(8, in: &data, at: 0x28)
        put32(0x90, in: &data, at: 0x30); put32(0xa000, in: &data, at: 0x34); put32(8, in: &data, at: 0x38)
        for i in 0..<32 { data[0x40 + i] = UInt8(i) }
        let report = try PayloadParser.inspect(data, fileName: "main.nso")
        try expect(report.format == "Nintendo NSO0", "NSO format")
        try expect(report.segments.count == 3, "NSO segment count")
        try expect(report.buildID == (0..<32).map { String(format: "%02x", $0) }.joined(), "NSO build ID offset")
        try expect(report.notes.contains("NSO XOM flag is not set."), "NSO XOM note")
    }

    static func testShortNSO() throws {
        var data = Data(repeating: 0, count: 0x80)
        putASCII("NSO0", in: &data, at: 0)
        do {
            _ = try PayloadParser.inspect(data, fileName: "truncated.nso")
            throw TestFailure.failed("Short NSO header should be rejected")
        } catch is PayloadInspectionError {
            // Expected: NSO0 requires its complete 0x100-byte header.
        }
    }

    static func testELF64() throws {
        var data = Data(repeating: 0, count: 0x100)
        data[0] = 0x7f; data[1] = 0x45; data[2] = 0x4c; data[3] = 0x46
        data[4] = 2; data[5] = 1; data[6] = 1
        put16(183, in: &data, at: 0x12)
        put64(64, in: &data, at: 0x20)
        put16(56, in: &data, at: 0x36); put16(1, in: &data, at: 0x38)
        put32(1, in: &data, at: 64); put32(5, in: &data, at: 68)
        put64(0xf0, in: &data, at: 72); put64(0x8000, in: &data, at: 80)
        put64(16, in: &data, at: 96); put64(32, in: &data, at: 104)
        let report = try PayloadParser.inspect(data, fileName: "hello.elf")
        try expect(report.format == "ELF64", "ELF format")
        try expect(report.architecture == "AArch64", "ELF architecture")
        try expect(report.segments.count == 1, "ELF PT_LOAD count")
    }

    static func testMalformedNRO() throws {
        var data = Data(repeating: 0, count: 0x100)
        putASCII("NRO0", in: &data, at: 0x10)
        put32(0x100, in: &data, at: 0x18)
        put32(0xfffffff0, in: &data, at: 0x20)
        put32(0x80, in: &data, at: 0x24)
        do {
            _ = try PayloadParser.inspect(data, fileName: "bad.nro")
            throw TestFailure.failed("Malformed NRO should be rejected")
        } catch is PayloadInspectionError {
            // Expected: the claimed segment extends past the declared file size.
        }
    }

    static func testUnknown() throws {
        do {
            _ = try PayloadParser.inspect(Data(repeating: 0, count: 128), fileName: "unknown.bin")
            throw TestFailure.failed("Unknown file should be rejected")
        } catch PayloadInspectionError.unsupported {
            // Expected.
        }
    }

    static func expect(_ condition: Bool, _ label: String) throws {
        if !condition { throw TestFailure.failed(label) }
    }

    static func putASCII(_ value: String, in data: inout Data, at offset: Int) {
        for (index, byte) in value.utf8.enumerated() { data[offset + index] = byte }
    }
    static func put16(_ value: UInt16, in data: inout Data, at offset: Int) {
        for i in 0..<2 { data[offset + i] = UInt8((value >> (i * 8)) & 0xff) }
    }
    static func put32(_ value: UInt32, in data: inout Data, at offset: Int) {
        for i in 0..<4 { data[offset + i] = UInt8((value >> (i * 8)) & 0xff) }
    }
    static func put64(_ value: UInt64, in data: inout Data, at offset: Int) {
        for i in 0..<8 { data[offset + i] = UInt8((value >> (i * 8)) & 0xff) }
    }
}

enum TestFailure: Error {
    case failed(String)
}
