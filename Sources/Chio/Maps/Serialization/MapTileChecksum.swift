import Foundation

/// Shared CRC32 framing integrity; detects accidental corruption, not authenticity.
enum MapTileChecksum {
    private static let checksumTable: [UInt32] = (0..<256).map { byte in
        var value = UInt32(byte)
        for _ in 0..<8 {
            if value & 1 == 1 { value = (value >> 1) ^ 0xedb88320 }
            else { value >>= 1 }
        }
        return value
    }

    static func crc32(_ data: Data) throws -> UInt32 {
        var value: UInt32 = 0xffffffff
        for (index, byte) in data.enumerated() {
            if index.isMultiple(of: 65_536) { try Task.checkCancellation() }
            value = checksumTable[Int((value ^ UInt32(byte)) & 255)] ^ (value >> 8)
        }
        return value ^ 0xffffffff
    }
}
