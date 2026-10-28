import Foundation

/// Bounded decoder for Chromium's persisted JSON-compatible structured clones.
/// No JavaScript is evaluated. Unknown wire versions/tags fail closed.
public enum BrowserCacheDecoder {
    public enum Failure: Error { case malformed, invalid(Int), unsupported(Int, Int) }
    public static func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= 32 * 1024 * 1024 else { throw Failure.malformed }
        var bytes = Array(data)
        if bytes.starts(with: [255, 17, 2]) { bytes = try snappy(Array(bytes.dropFirst(3))) }
        let offset: Int
        if bytes.starts(with: [255, 21, 254]), bytes.count > 16 { offset = 15 }
        else { offset = 0 }
        guard bytes.count > offset + 1, bytes[offset] == 255, [15, 16].contains(bytes[offset + 1]) else { throw Failure.malformed }
        var reader = Reader(bytes: bytes, index: offset + 2)
        guard let object = try reader.value(depth: 0) as? [String: Any] else { throw Failure.malformed }
        return object
    }
    static func snappy(_ bytes: [UInt8]) throws -> [UInt8] {
        var r = Reader(bytes: bytes)
        let size = try r.varint()
        guard size <= 64 * 1024 * 1024 else { throw Failure.malformed }
        var output: [UInt8] = []; output.reserveCapacity(size)
        while r.index < bytes.count {
            let tag = Int(try r.byte()), kind = tag & 3
            var length = 0, offset = 0
            if kind == 0 {
                length = (tag >> 2) + 1
                if length > 60 { length = try r.little(length - 60) + 1 }
                guard length <= size - output.count else { throw Failure.malformed }
                output += try r.take(length)
            } else {
                if kind == 1 { length = 4 + ((tag >> 2) & 7); offset = ((tag & 224) << 3) | Int(try r.byte()) }
                else { length = 1 + (tag >> 2); offset = try r.little(kind == 2 ? 2 : 4) }
                guard offset > 0, offset <= output.count, length <= size - output.count else { throw Failure.malformed }
                for _ in 0..<length { output.append(output[output.count - offset]) }
            }
        }
        guard output.count == size else { throw Failure.malformed }; return output
    }
    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var objects: [Any?] = []
        var collectionSlots = 0
        mutating func byte() throws -> UInt8 { guard index < bytes.count else { throw Failure.invalid(index) }; defer { index += 1 }; return bytes[index] }
        mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, n <= bytes.count - index else { throw Failure.invalid(index) }
            defer { index += n }; return Array(bytes[index..<index+n])
        }
        mutating func little(_ n: Int) throws -> Int { var v = 0; for k in 0..<n { v |= Int(try byte()) << (k * 8) }; return v }
        mutating func varint() throws -> Int {
            var value = 0
            for shift in stride(from: 0, to: 35, by: 7) { let b = try byte(); value |= Int(b & 127) << shift; if b < 128 { return value } }
            throw Failure.invalid(index)
        }
        mutating func tag() throws -> UInt8 { var b = try byte(); while b == 0 { b = try byte() }; return b }
        mutating func value(depth: Int) throws -> Any {
            guard depth < 128, objects.count < 200_000 else { throw Failure.invalid(index) }
            let t = try tag()
            switch t {
            case 48, 95, 45: return NSNull()
            case 84: return true
            case 70: return false
            case 73: let v = try varint(); return (v >> 1) ^ -(v & 1)
            case 85: return try varint()
            case 78:
                let b = try take(8); var bits: UInt64 = 0
                for (i, v) in b.enumerated() { bits |= UInt64(v) << (i * 8) }
                return Double(bitPattern: bits)
            case 34, 83, 99:
                let b = try take(try varint())
                guard let text = String(bytes: b, encoding: t == 34 ? .isoLatin1 : t == 99 ? .utf16LittleEndian : .utf8) else { throw Failure.invalid(index) }
                return text
            case 94:
                let ref = try varint(); guard ref < objects.count, let value = objects[ref] else { throw Failure.invalid(index) }; return value
            case 111:
                let ref = objects.count; objects.append(nil)
                var object: [String: Any] = [:], count = 0
                while true {
                    let marker = try tag(); if marker == 123 { break }; index -= 1
                    let key = try value(depth: depth + 1)
                    let name: String
                    if let s = key as? String { name = s } else if let n = key as? Int { name = String(n) } else if let n = key as? Double, n.isFinite { name = String(format: "%.0f", n) } else { throw Failure.invalid(index) }
                    object[name] = try value(depth: depth + 1); count += 1
                    guard count <= 200_000 else { throw Failure.invalid(index) }
                }
                guard try varint() == count else { throw Failure.invalid(index) }; objects[ref] = object; return object
            case 65, 97:
                let length = try varint(); guard length <= 200_000 else { throw Failure.invalid(index) }
                collectionSlots += length
                guard collectionSlots <= 1_000_000 else { throw Failure.invalid(index) }
                let ref = objects.count; objects.append(nil)
                var array = Array<Any>(repeating: NSNull(), count: length)
                if t == 65 { for i in 0..<length { array[i] = try value(depth: depth + 1) } }
                var count = 0
                while true {
                    let marker = try tag(); if marker == (t == 65 ? 36 : 64) { break }; index -= 1
                    let key = try value(depth: depth + 1), item = try value(depth: depth + 1)
                    if let n = key as? Int, n >= 0, n < length { array[n] = item }
                    count += 1; guard count <= 200_000 else { throw Failure.invalid(index) }
                }
                guard try varint() == count, try varint() == length else { throw Failure.invalid(index) }
                objects[ref] = array; return array
            case 63: _ = try varint(); return try value(depth: depth + 1)
            default: throw Failure.unsupported(Int(t), index - 1)
            }
        }
    }
}
