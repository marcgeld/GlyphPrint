import Foundation
import OSLog

public enum GlyphProtocol {
    public static let preamble1 = Data(hex: "5178a80001000000ff5178a30001000000ff")
    // Reference: https://github.com/rbaron/catprinter/blob/main/catprinter/cmds.py
    public static let preamble2 = GlyphPacketBuilder.makePacket(command: 0xA4, payload: Data([0x32]))
        + GlyphPacketBuilder.makePacket(command: 0xBE, payload: Data([0x00]))

    public static let pageStart = GlyphPacketBuilder.makePacket(
        command: 0xA6, payload: Data([0xAA, 0x55, 0x17, 0x38, 0x44, 0x5F, 0x5F, 0x5F, 0x44, 0x38, 0x2C]))
    public static let pageEnd = GlyphPacketBuilder.makePacket(
        command: 0xA6, payload: Data([0xAA, 0x55, 0x17, 0, 0, 0, 0, 0, 0, 0, 0x17]))
    // BD selects feed speed; A1 advances the paper by a little-endian step count.
    public static let feedPaper = GlyphPacketBuilder.makePacket(command: 0xBD, payload: Data([0x19]))
        + GlyphPacketBuilder.makePacket(command: 0xA1, payload: Data([0x30, 0x00]))

    private static let logger = Logger.glyphPrintProtocol

    public static func buildPrintJob(from raster: RasterImage, addFeedAfterPrint: Bool = true) throws -> [Data] {
        guard raster.width > 0, raster.width % 8 == 0 else {
            throw GlyphPrintError.unsupportedImageWidth(raster.width)
        }

        var packets: [Data] = [preamble1, preamble2, pageStart]
        packets.append(contentsOf: try makeRasterPackets(from: raster))
        if addFeedAfterPrint {
            packets.append(feedPaper)
        }
        packets.append(pageEnd)
        return packets
    }

    public static func makeRasterPackets(from raster: RasterImage) throws -> [Data] {
        guard raster.width > 0, raster.width % 8 == 0 else {
            throw GlyphPrintError.unsupportedImageWidth(raster.width)
        }

        guard raster.height > 0, raster.height <= Int(UInt16.max) + 1,
              raster.width / 8 <= Int(UInt16.max) - 2 else {
            throw GlyphPrintError.invalidImage
        }

        let rowByteWidth = raster.width / 8
        let expectedSize = raster.height * rowByteWidth
        guard raster.bytes.count == expectedSize else {
            throw GlyphPrintError.invalidImage
        }
        logger.debug("Building raster packets for \(raster.height, privacy: .public) rows")

        return (0..<raster.height).map { rowIndex in
            let start = rowIndex * rowByteWidth
            let end = start + rowByteWidth
            let rowBytes = raster.bytes.subdata(in: start..<end)
            return makeRasterRowPacket(rowBytes: rowBytes)
        }
    }

    /// RasterImage stores the leftmost pixel in bit 7; the printer expects it in bit 0.
    /// A2 contains only bitmap bytes, with no row number prefix.
    public static func makeRasterRowPacket(rowBytes: Data) -> Data {
        let payload = Data(rowBytes.map { byte in
            var value = byte
            value = (value >> 4) | (value << 4)
            value = ((value & 0xCC) >> 2) | ((value & 0x33) << 2)
            return ((value & 0xAA) >> 1) | ((value & 0x55) << 1)
        })
        return GlyphPacketBuilder.makePacket(command: 0xA2, payload: payload)
    }

    @available(*, deprecated, message: "Raster packets do not contain row numbers. Use makeRasterRowPacket(rowBytes:).")
    public static func makeRasterRowPacket(rowBytes: Data, rowIndex: Int) -> Data {
        makeRasterRowPacket(rowBytes: rowBytes)
    }
}
