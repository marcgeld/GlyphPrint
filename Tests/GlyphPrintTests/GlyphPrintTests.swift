import Testing
import Foundation
import CoreGraphics
@testable import GlyphPrint

@Test func crc8Vector() {
    let value = CRC8.checksum(Data("123456789".utf8))
    #expect(value == 0xF4)
}

@Test func packetBuilderFramesPayload() {
    let packet = GlyphPacketBuilder.makePacket(command: 0xA2, payload: Data([0x34, 0x12, 0xAA]))
    #expect(packet.prefix(6) == Data([0x51, 0x78, 0xA2, 0x00, 0x03, 0x00]))
    #expect(packet.suffix(1) == Data([0xFF]))
    #expect(packet[6] == 0x34)
    #expect(packet[7] == 0x12)
    #expect(packet[8] == 0xAA)
}

@Test func rasterRowPacketIncludesLineNumber() {
    let packet = GlyphProtocol.makeRasterRowPacket(rowBytes: Data([0xAA, 0x55]), rowIndex: 7)
    #expect(packet.prefix(6) == Data([0x51, 0x78, 0xA2, 0x00, 0x04, 0x00]))
    #expect(packet[6] == 0x07)
    #expect(packet[7] == 0x00)
    #expect(packet[8] == 0xAA)
    #expect(packet[9] == 0x55)
}

@Test func packBitsSingleRow() {
    let bits: [UInt8] = [1, 0, 1, 0, 1, 0, 1, 0]
    let packed = MonochromeRasterizer.packBits(bits, width: 8, height: 1)
    #expect(packed == Data([0b10101010]))
}

@Test func packBitsMultipleRows() {
    let row1: [UInt8] = [1, 1, 1, 1, 0, 0, 0, 0]
    let row2: [UInt8] = [0, 0, 0, 0, 1, 1, 1, 1]
    let bits = row1 + row2
    let packed = MonochromeRasterizer.packBits(bits, width: 8, height: 2)
    #expect(packed == Data([0b11110000, 0b00001111]))
}

@Test func makePacketsForQRCodeProducesPreambleAndRaster() throws {
    let transport = MockTransport()
    let printer = GlyphPrinter(transport: transport)
    let packets = try printer.makePacketsForQRCode("hello")
    #expect(packets.count > 4)
    #expect(packets[0] == GlyphProtocol.preamble1)
    #expect(packets[1] == GlyphProtocol.preamble2)
    #expect(packets[2] == GlyphProtocol.pageStart)
    #expect(packets[packets.count - 2] == GlyphProtocol.pageEnd)
}

@Test func printSendsPacketsToTransport() async throws {
    let transport = MockTransport()
    let printer = GlyphPrinter(transport: transport)
    let image = try makeCheckerboardImage(width: 16, height: 16)

    try await printer.connect(timeout: .seconds(1))
    try await printer.print(image: image)

    let sent = await transport.snapshot()
    #expect(!sent.isEmpty)
    #expect(sent.first == GlyphProtocol.preamble1)
}

@Test func buildPrintJobIncludesFeedPaperByDefault() throws {
    let raster = RasterImage(width: 8, height: 1, bytes: Data([0xAA]))
    let packets = try GlyphProtocol.buildPrintJob(from: raster)
    #expect(packets.last == GlyphProtocol.feedPaper)
}

@Test func buildPrintJobOmitsFeedWhenDisabled() throws {
    let raster = RasterImage(width: 8, height: 1, bytes: Data([0xAA]))
    let packets = try GlyphProtocol.buildPrintJob(from: raster, addFeedAfterPrint: false)
    #expect(packets.last == GlyphProtocol.pageEnd)
}

@Test func makeRasterPacketsCountMatchesImageHeight() throws {
    let height = 3
    let raster = RasterImage(width: 8, height: height, bytes: Data(repeating: 0xFF, count: height))
    let packets = try GlyphProtocol.makeRasterPackets(from: raster)
    #expect(packets.count == height)
}

@Test func makeRasterPacketsThrowsOnTruncatedData() {
    let raster = RasterImage(width: 8, height: 2, bytes: Data([0xAA]))  // needs 2 bytes, only 1
    #expect(throws: GlyphPrintError.self) {
        _ = try GlyphProtocol.makeRasterPackets(from: raster)
    }
}

@Test func hexDataRoundTrips() {
    let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let hex = original.hexString
    #expect(hex == "deadbeef")
    #expect(Data(hex: hex) == original)
}

@Test func hexDataHandlesEmptyString() {
    #expect(Data(hex: "").isEmpty)
}

@Test func hexDataHandlesOddLengthString() {
    // Odd-length string should only parse complete pairs
    let data = Data(hex: "ABC")
    #expect(data == Data([0xAB]))
}

@Test func hexDataSkipsInvalidCharacters() {
    // "ZZ" is not valid hex; it should be skipped
    let data = Data(hex: "AAZZ")
    #expect(data == Data([0xAA]))
}

// MARK: - Helpers

private func makeCheckerboardImage(width: Int, height: Int) throws -> CGImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let idx = (y * width + x) * 4
            let black = ((x + y) % 2 == 0)
            let value: UInt8 = black ? 0 : 255
            pixels[idx] = value
            pixels[idx + 1] = value
            pixels[idx + 2] = value
            pixels[idx + 3] = 255
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        throw GlyphPrintError.invalidImage
    }
    guard let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw GlyphPrintError.invalidImage
    }
    return image
}

private actor MockTransport: GlyphPrinterTransport {
    private var packets: [Data] = []

    func connect(timeout: Duration) async throws {}
    nonisolated func disconnect() {}

    func send(_ data: Data) async throws {
        packets.append(data)
    }

    func snapshot() -> [Data] {
        packets
    }
}
