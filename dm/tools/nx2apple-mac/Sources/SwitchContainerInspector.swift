import Foundation

struct SwitchContainerEntry: Equatable {
    let name: String
    let offset: UInt64
    let size: UInt64
}

struct SwitchContainerSummary: Equatable {
    let format: String
    let entries: [SwitchContainerEntry]
}

enum SwitchContainerError: Error, LocalizedError {
    case truncated
    case unreasonableEntryCount
    case invalidStringTable
    case invalidEntry(String)
    case duplicateName(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .truncated: return "Container is truncated."
        case .unreasonableEntryCount: return "Container declares an unreasonable number of entries."
        case .invalidStringTable: return "Container contains an invalid filename string table."
        case .invalidEntry(let name): return "Container entry has an invalid data range: \(name)"
        case .duplicateName(let name): return "Container contains a duplicate filename: \(name)"
        case .unsupported: return "File is not a supported PFS0 or HFS0 container."
        }
    }
}

/// Bounds-checked, read-only parser for PFS0/HFS0 directory tables.
/// It never decrypts, extracts, modifies, or executes contained files.
enum SwitchContainerInspector {
    static func inspect(_ data: Data, maximumEntries: UInt32 = 100_000) throws -> SwitchContainerSummary {
        // Keep mapped file data mapped; do not duplicate multi-gigabyte containers in RAM.
        let bytes = data
        guard bytes.count >= 0x10 else { throw SwitchContainerError.truncated }
        let magic = String(bytes: bytes[0..<4], encoding: .ascii) ?? ""
        let entrySize: UInt64
        switch magic {
        case "PFS0": entrySize = 0x18
        case "HFS0": entrySize = 0x40
        default: throw SwitchContainerError.unsupported
        }

        let count = try u32(bytes, at: 4)
        let stringBytes = try u32(bytes, at: 8)
        guard count <= maximumEntries else { throw SwitchContainerError.unreasonableEntryCount }

        let tableBytes = UInt64(count).multipliedReportingOverflow(by: entrySize)
        guard !tableBytes.overflow else { throw SwitchContainerError.truncated }
        let stringsStart = UInt64(0x10).addingReportingOverflow(tableBytes.partialValue)
        guard !stringsStart.overflow else { throw SwitchContainerError.truncated }
        let payloadStart = stringsStart.partialValue.addingReportingOverflow(UInt64(stringBytes))
        guard !payloadStart.overflow, payloadStart.partialValue <= UInt64(bytes.count) else {
            throw SwitchContainerError.truncated
        }

        let stringStart = Int(stringsStart.partialValue)
        let stringEnd = stringStart + Int(stringBytes)
        let payloadBase = payloadStart.partialValue
        var entries: [SwitchContainerEntry] = []
        entries.reserveCapacity(Int(count))
        var names = Set<String>()

        for index in 0..<Int(count) {
            let entryOffset = 0x10 + index * Int(entrySize)
            let relativeOffset = try u64(bytes, at: entryOffset)
            let size = try u64(bytes, at: entryOffset + 8)
            let nameOffset = try u32(bytes, at: entryOffset + 16)
            guard UInt64(nameOffset) < UInt64(stringBytes) else {
                throw SwitchContainerError.invalidStringTable
            }
            let nameStart = stringStart + Int(nameOffset)
            guard nameStart >= stringStart, nameStart < stringEnd,
                  let nul = bytes[nameStart..<stringEnd].firstIndex(of: 0), nul > nameStart,
                  let name = String(bytes: bytes[nameStart..<nul], encoding: .utf8),
                  !name.contains("/"), !name.contains("\\"),
                  name != ".", name != ".." else {
                throw SwitchContainerError.invalidStringTable
            }
            guard names.insert(name).inserted else {
                throw SwitchContainerError.duplicateName(name)
            }

            let absolute = payloadBase.addingReportingOverflow(relativeOffset)
            guard !absolute.overflow else { throw SwitchContainerError.invalidEntry(name) }
            let end = absolute.partialValue.addingReportingOverflow(size)
            guard !end.overflow, end.partialValue <= UInt64(bytes.count) else {
                throw SwitchContainerError.invalidEntry(name)
            }
            entries.append(SwitchContainerEntry(name: name, offset: absolute.partialValue, size: size))
        }
        return SwitchContainerSummary(format: magic, entries: entries)
    }

    private static func u32(_ bytes: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= bytes.count - 4 else { throw SwitchContainerError.truncated }
        return UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }

    private static func u64(_ bytes: Data, at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset <= bytes.count - 8 else { throw SwitchContainerError.truncated }
        var value: UInt64 = 0
        for byte in 0..<8 { value |= UInt64(bytes[offset + byte]) << (byte * 8) }
        return value
    }
}
