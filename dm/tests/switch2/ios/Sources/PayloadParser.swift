import Foundation

struct PayloadSegment {
    let name: String
    let fileOffset: UInt64
    let fileSize: UInt64
    let memoryOffset: UInt64
    let memorySize: UInt64
    let flags: UInt32?
}

struct PayloadReport {
    let fileName: String
    let format: String
    let architecture: String
    let version: String
    let buildID: String
    let fileSize: Int
    let segments: [PayloadSegment]
    let notes: [String]
}

enum PayloadInspectionError: Error, LocalizedError {
    case tooSmall
    case malformed(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .tooSmall: return "The selected file is too small to contain a supported executable header."
        case .malformed(let reason): return "The file header is malformed: \(reason)"
        case .unsupported: return "Unsupported file format. Supported inspection formats are NRO0, NSO0 and ELF64."
        }
    }
}

enum PayloadParser {
    static func inspect(_ data: Data, fileName: String) throws -> PayloadReport {
        if data.count >= 0x80, ascii(data, at: 0x10, count: 4) == "NRO0" {
            return try inspectNRO(data, fileName: fileName)
        }
        if data.count >= 0x100, ascii(data, at: 0, count: 4) == "NSO0" {
            return try inspectNSO(data, fileName: fileName)
        }
        if data.count >= 64, data[0] == 0x7f, data[1] == 0x45, data[2] == 0x4c, data[3] == 0x46 {
            return try inspectELF(data, fileName: fileName)
        }
        throw PayloadInspectionError.unsupported
    }

    private static func inspectNRO(_ data: Data, fileName: String) throws -> PayloadReport {
        let declaredSize = try u32(data, 0x18)
        guard declaredSize >= 0x80, Int(declaredSize) <= data.count else {
            throw PayloadInspectionError.malformed("NRO declared size is outside the file.")
        }
        let fields: [(String, Int, Int)] = [("text", 0x20, 0x24), ("rodata", 0x28, 0x2c), ("data", 0x30, 0x34)]
        var segments: [PayloadSegment] = []
        for (name, offsetField, sizeField) in fields {
            let offset = UInt64(try u32(data, offsetField))
            let size = UInt64(try u32(data, sizeField))
            try checkRange(offset: offset, size: size, limit: UInt64(declaredSize), label: name)
            segments.append(PayloadSegment(name: name, fileOffset: offset, fileSize: size,
                                           memoryOffset: offset, memorySize: size, flags: nil))
        }
        let bss = UInt64(try u32(data, 0x38))
        if bss > 0 {
            segments.append(PayloadSegment(name: "bss", fileOffset: 0, fileSize: 0,
                                           memoryOffset: 0, memorySize: bss, flags: nil))
        }
        let buildID = hex(data.subdata(in: 0x40..<0x60))
        return PayloadReport(fileName: fileName, format: "Nintendo NRO0", architecture: "AArch64 (64-bit)",
                             version: String(try u32(data, 0x14)), buildID: buildID,
                             fileSize: data.count, segments: segments,
                             notes: ["Header inspected only; no code was executed.",
                                     "NRO is the original Switch homebrew container. This does not establish Switch 2 title compatibility."])
    }

    private static func inspectNSO(_ data: Data, fileName: String) throws -> PayloadReport {
        let version = try u32(data, 0x04)
        let flags = try u32(data, 0x0c)
        let specs: [(String, Int, Int, Int, Int)] = [
            ("text", 0x10, 0x14, 0x18, 0x60),
            ("rodata", 0x20, 0x24, 0x28, 0x64),
            ("data", 0x30, 0x34, 0x38, 0x68)
        ]
        var segments: [PayloadSegment] = []
        for (name, fileField, memoryField, sizeField, compressedField) in specs {
            let fileOffset = UInt64(try u32(data, fileField))
            let memoryOffset = UInt64(try u32(data, memoryField))
            let memorySize = UInt64(try u32(data, sizeField))
            let bit: UInt32 = name == "text" ? 0 : (name == "rodata" ? 1 : 2)
            let isCompressed = (flags & (1 << bit)) != 0
            let fileSize = isCompressed ? UInt64(try u32(data, compressedField)) : memorySize
            try checkRange(offset: fileOffset, size: fileSize, limit: UInt64(data.count), label: name)
            segments.append(PayloadSegment(name: name, fileOffset: fileOffset, fileSize: fileSize,
                                           memoryOffset: memoryOffset, memorySize: memorySize, flags: nil))
        }
        let buildID = hex(data.subdata(in: 0x40..<0x60))
        return PayloadReport(fileName: fileName, format: "Nintendo NSO0", architecture: "AArch64 (64-bit)",
                             version: String(version), buildID: buildID, fileSize: data.count,
                             segments: segments,
                             notes: ["Header inspected only; compressed sections are not decompressed.",
                                     (flags & 0x40) != 0 ? "NSO requests execute-only text (XOM)." : "NSO XOM flag is not set.",
                                     (flags & 0x80) != 0 ? "NSO uses ZBIC-compressed segments." : "NSO ZBIC flag is not set.",
                                     "NSO is a shared module container; this header alone does not identify the console generation or prove ABI compatibility."])
    }

    private static func inspectELF(_ data: Data, fileName: String) throws -> PayloadReport {
        guard data[4] == 2 else { throw PayloadInspectionError.malformed("Only ELF64 is supported.") }
        guard data[5] == 1 else { throw PayloadInspectionError.malformed("Only little-endian ELF is supported.") }
        let machine = try u16(data, 0x12)
        let architecture = machine == 183 ? "AArch64" : "ELF machine \(machine)"
        let phoff = try u64(data, 0x20)
        let phentsize = UInt64(try u16(data, 0x36))
        let phnum = UInt64(try u16(data, 0x38))
        guard phentsize >= 56 else { throw PayloadInspectionError.malformed("ELF program-header entries are too small.") }
        let tableSize = phentsize.multipliedReportingOverflow(by: phnum)
        guard !tableSize.overflow else { throw PayloadInspectionError.malformed("ELF program-header table overflow.") }
        try checkRange(offset: phoff, size: tableSize.partialValue, limit: UInt64(data.count), label: "program-header table")
        var segments: [PayloadSegment] = []
        for index in 0..<phnum {
            let base = Int(phoff + index * phentsize)
            let type = try u32(data, base)
            guard type == 1 else { continue } // PT_LOAD
            let segmentFlags = try u32(data, base + 4)
            let fileOffset = try u64(data, base + 8)
            let memoryOffset = try u64(data, base + 16)
            let fileSize = try u64(data, base + 32)
            let memorySize = try u64(data, base + 40)
            try checkRange(offset: fileOffset, size: fileSize, limit: UInt64(data.count), label: "ELF load segment")
            segments.append(PayloadSegment(name: "PT_LOAD \(segments.count)", fileOffset: fileOffset,
                                           fileSize: fileSize, memoryOffset: memoryOffset,
                                           memorySize: memorySize, flags: segmentFlags))
        }
        return PayloadReport(fileName: fileName, format: "ELF64", architecture: architecture,
                             version: "ELF version \(data[6])", buildID: "Not extracted",
                             fileSize: data.count, segments: segments,
                             notes: ["Header and PT_LOAD entries inspected only; relocations, imports and code are not executed."])
    }

    private static func checkRange(offset: UInt64, size: UInt64, limit: UInt64, label: String) throws {
        let end = offset.addingReportingOverflow(size)
        guard !end.overflow, end.partialValue <= limit else {
            throw PayloadInspectionError.malformed("\(label) segment exceeds the file bounds.")
        }
    }

    private static func ascii(_ data: Data, at offset: Int, count: Int) -> String? {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { return nil }
        return String(data: data.subdata(in: offset..<(offset + count)), encoding: .ascii)
    }

    private static func u16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= data.count - 2 else { throw PayloadInspectionError.tooSmall }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { throw PayloadInspectionError.tooSmall }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
               (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func u64(_ data: Data, _ offset: Int) throws -> UInt64 {
        guard offset >= 0, offset <= data.count - 8 else { throw PayloadInspectionError.tooSmall }
        var value: UInt64 = 0
        for index in 0..<8 { value |= UInt64(data[offset + index]) << (index * 8) }
        return value
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
