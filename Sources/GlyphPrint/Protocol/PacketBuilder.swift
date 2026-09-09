import Foundation

public enum GlyphPacketBuilder {
    /// Packet framing for the common 0x5178 BLE printer protocol.
    ///
    /// Format used here:
    /// 0x51 0x78 <command> 0x00 <len_lo> <len_hi> <payload...> <crc8(payload)> 0xFF
    public static func makePacket(command: UInt8, payload: Data = Data()) -> Data {
        precondition(payload.count <= UInt16.max)
        let length = UInt16(payload.count)
        var data = Data()
        data.reserveCapacity(8 + payload.count)
        data.append(0x51)
        data.append(0x78)
        data.append(command)
        data.append(0x00)
        data.append(UInt8(length & 0x00ff))
        data.append(UInt8((length >> 8) & 0x00ff))
        data.append(payload)
        data.append(CRC8.checksum(payload))
        data.append(0xFF)
        return data
    }
}
