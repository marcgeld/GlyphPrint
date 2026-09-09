import Foundation

public enum CRC8 {
    /// CRC-8 with polynomial 0x07, initial value 0x00.
    public static func checksum(_ data: Data) -> UInt8 {
        var crc: UInt8 = 0x00
        for byte in data {
            crc ^= byte
            for _ in 0..<8 {
                if (crc & 0x80) != 0 {
                    crc = (crc << 1) ^ 0x07
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }
}
