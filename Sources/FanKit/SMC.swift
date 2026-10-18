import Foundation
import CSMC

public enum SMCError: Error, CustomStringConvertible {
    case openFailed(Int32)
    case keyNotFound(String)
    case ioError(String, Int32)
    case unsupportedType(String, String)

    public var description: String {
        switch self {
        case .openFailed(let kr): return "Could not open AppleSMC (kern_return \(kr))"
        case .keyNotFound(let k): return "SMC key \(k) not found"
        case .ioError(let k, let kr): return "SMC I/O error on \(k) (code \(kr))"
        case .unsupportedType(let k, let t): return "SMC key \(k) has unsupported type \(t)"
        }
    }
}

/// Type/size description of an SMC key.
public struct SMCKeyInfo: Equatable {
    public let size: Int
    public let type: String   // four-char type code such as "flt ", "sp78", "fpe2", "ui8 "
    public let attributes: UInt8

    /// Raw type code as FourCC string.
    static func fourCC(_ v: UInt32) -> String {
        let bytes = [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

/// A connection to the System Management Controller. Not thread-safe; use from one queue.
public final class SMC {
    private var conn: io_connect_t = 0
    private var infoCache: [String: SMCKeyInfo] = [:]

    public init() throws {
        let kr = smc_open(&conn)
        if kr != 0 { throw SMCError.openFailed(kr) }
    }

    deinit { smc_close(conn) }

    // MARK: Key enumeration

    public func keyCount() throws -> Int {
        var n: UInt32 = 0
        let kr = smc_key_count(conn, &n)
        if kr != 0 { throw SMCError.ioError("#KEY", kr) }
        return Int(n)
    }

    public func allKeys() throws -> [String] {
        let n = try keyCount()
        var keys: [String] = []
        keys.reserveCapacity(n)
        var buf = [CChar](repeating: 0, count: 5)
        for i in 0..<n {
            if smc_key_at_index(conn, UInt32(i), &buf) == 0 {
                keys.append(String(cString: buf))
            }
        }
        return keys
    }

    public func info(for key: String) -> SMCKeyInfo? {
        if let cached = infoCache[key] { return cached }
        var raw = smc_key_info_t()
        let kr = smc_key_info(conn, key, &raw)
        guard kr == 0 else { return nil }
        let info = SMCKeyInfo(size: Int(raw.dataSize), type: SMCKeyInfo.fourCC(raw.dataType), attributes: raw.dataAttributes)
        infoCache[key] = info
        return info
    }

    public func hasKey(_ key: String) -> Bool { info(for: key) != nil }

    // MARK: Raw I/O

    public func readBytes(_ key: String) throws -> (SMCKeyInfo, [UInt8]) {
        var raw = smc_key_info_t()
        var bytes = [UInt8](repeating: 0, count: 32)
        let kr = smc_read(conn, key, &raw, &bytes)
        if kr != 0 {
            if kr == 0x184 { throw SMCError.keyNotFound(key) }  // 0x84 = key not found
            throw SMCError.ioError(key, kr)
        }
        let info = SMCKeyInfo(size: Int(raw.dataSize), type: SMCKeyInfo.fourCC(raw.dataType), attributes: raw.dataAttributes)
        infoCache[key] = info
        return (info, Array(bytes.prefix(info.size)))
    }

    public func writeBytes(_ key: String, _ bytes: [UInt8]) throws {
        let kr = bytes.withUnsafeBufferPointer { smc_write(conn, key, $0.baseAddress, UInt32(bytes.count)) }
        if kr != 0 { throw SMCError.ioError(key, kr) }
    }

    // MARK: Typed access

    /// Reads a numeric key and decodes it according to its SMC type.
    public func readDouble(_ key: String) throws -> Double {
        let (info, b) = try readBytes(key)
        guard let v = SMC.decode(info: info, bytes: b) else {
            throw SMCError.unsupportedType(key, info.type)
        }
        return v
    }

    public func readString(_ key: String) throws -> String {
        let (_, b) = try readBytes(key)
        let trimmed = b.prefix { $0 != 0 }
        return String(bytes: trimmed, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    public func writeDouble(_ key: String, _ value: Double) throws {
        guard let info = info(for: key) else { throw SMCError.keyNotFound(key) }
        guard let bytes = SMC.encode(info: info, value: value) else {
            throw SMCError.unsupportedType(key, info.type)
        }
        try writeBytes(key, bytes)
    }

    // MARK: Codec

    static func decode(info: SMCKeyInfo, bytes b: [UInt8]) -> Double? {
        let t = info.type
        switch t {
        case "flt ":
            guard b.count >= 4 else { return nil }
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            let f = Float(bitPattern: bits)
            return f.isFinite ? Double(f) : nil
        case "ui8 ", "ui8":
            return b.count >= 1 ? Double(b[0]) : nil
        case "ui16":
            return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case "ui32":
            return b.count >= 4 ? Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])) : nil
        case "si8 ", "si8":
            return b.count >= 1 ? Double(Int8(bitPattern: b[0])) : nil
        case "si16":
            return b.count >= 2 ? Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) : nil
        case "flag":
            return b.count >= 1 ? Double(b[0]) : nil
        default:
            // Fixed point: "fpXY" unsigned, "spXY" signed, Y = fractional bits (hex digit), 16-bit big-endian.
            let chars = Array(t)
            if chars.count == 4, (chars[0] == "f" || chars[0] == "s"), chars[1] == "p",
               let frac = Int(String(chars[3]), radix: 16), b.count >= 2 {
                let raw = UInt16(b[0]) << 8 | UInt16(b[1])
                let divisor = Double(1 << frac)
                if chars[0] == "s" {
                    return Double(Int16(bitPattern: raw)) / divisor
                } else {
                    return Double(raw) / divisor
                }
            }
            return nil
        }
    }

    static func encode(info: SMCKeyInfo, value: Double) -> [UInt8]? {
        let t = info.type
        switch t {
        case "flt ":
            let bits = Float(value).bitPattern
            return [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
        case "ui8 ", "ui8", "flag":
            return [UInt8(max(0, min(255, value.rounded())))]
        case "ui16":
            let v = UInt16(max(0, min(65535, value.rounded())))
            return [UInt8(v >> 8), UInt8(v & 0xff)]
        case "ui32":
            let v = UInt32(max(0, min(4294967295, value.rounded())))
            return [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]
        default:
            let chars = Array(t)
            if chars.count == 4, (chars[0] == "f" || chars[0] == "s"), chars[1] == "p",
               let frac = Int(String(chars[3]), radix: 16) {
                let scaled = value * Double(1 << frac)
                if chars[0] == "s" {
                    let v = UInt16(bitPattern: Int16(max(-32768, min(32767, scaled.rounded()))))
                    return [UInt8(v >> 8), UInt8(v & 0xff)]
                } else {
                    let v = UInt16(max(0, min(65535, scaled.rounded())))
                    return [UInt8(v >> 8), UInt8(v & 0xff)]
                }
            }
            return nil
        }
    }
}
