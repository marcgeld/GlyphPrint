import Foundation
import OSLog

public enum GlyphProtocol {
    public static let preamble1 = Data(hex: "5178a80001000000ff5178a30001000000ff")
    public static let preamble2 = Data(hex: "5178bb0001000107ff")

    // These are baseline commands inferred from public reverse-engineering work.
    // They are intentionally isolated here so per-model variants can be introduced later.
    public static let pageStart = GlyphPacketBuilder.makePacket(command: 0xA6, payload: Data([0x01]))
    public static let pageEnd = GlyphPacketBuilder.makePacket(command: 0xA1, payload: Data([0x01]))
    public static let feedPaper = GlyphPacketBuilder.makePacket(command: 0xBD, payload: Data([0x19]))

    private static let logger = Logger.glyphPrintProtocol

    public static func buildPrintJob(from raster: RasterImage, addFeedAfterPrint: Bool = true) throws -> [Data] {
        guard raster.width % 8 == 0 else {
            throw GlyphPrintError.unsupportedImageWidth(raster.width)
        }

        var packets: [Data] = [preamble1, preamble2, pageStart]
        packets.append(contentsOf: try makeRasterPackets(from: raster))
        packets.append(pageEnd)
        if addFeedAfterPrint {
            packets.append(feedPaper)
        }
        return packets
    }

    public static func makeRasterPackets(from raster: RasterImage) throws -> [Data] {
        let rowByteWidth = raster.width / 8
        let expectedSize = raster.height * rowByteWidth
        guard raster.bytes.count >= expectedSize else {
            throw GlyphPrintError.invalidImage
        }
        logger.debug("Building raster packets for \(raster.height, privacy: .public) rows")

        return (0..<raster.height).map { rowIndex in
            let start = rowIndex * rowByteWidth
            let end = start + rowByteWidth
            let rowBytes = raster.bytes.subdata(in: start..<end)
            return makeRasterRowPacket(rowBytes: rowBytes, rowIndex: rowIndex)
        }
    }

    public static func makeRasterRowPacket(rowBytes: Data, rowIndex: Int = 0) -> Data {
        var payload = Data()
        let line = UInt16(truncatingIfNeeded: rowIndex)
        payload.append(UInt8(line & 0x00ff))
        payload.append(UInt8((line >> 8) & 0x00ff))
        payload.append(rowBytes)
        return GlyphPacketBuilder.makePacket(command: 0xA2, payload: payload)
    }
}
