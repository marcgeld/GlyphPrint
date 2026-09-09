import Testing
import Foundation
import CoreGraphics
import Vision
@testable import GlyphPrint

@Test func latticeCommandsMatchReferenceBytes() {
    #expect(GlyphProtocol.pageStart == Data(hex: "5178a6000b00aa551738445f5f5f44382ca1ff"))
    #expect(GlyphProtocol.pageEnd == Data(hex: "5178a6000b00aa5517000000000000001711ff"))
    #expect(GlyphProtocol.feedPaper == Data(hex: "5178bd000100194fff5178a10002003000f9ff"))
}

@Test func fullWidthRowContainsExactly48BitmapBytes() {
    let packet = GlyphProtocol.makeRasterRowPacket(rowBytes: Data(repeating: 0x80, count: 48))
    #expect(packet.count == 56)
    #expect(packet.prefix(6) == Data([0x51, 0x78, 0xA2, 0, 48, 0]))
    #expect(packet[6..<54] == Data(repeating: 1, count: 48))
}

@Test func printerRasterDecodesToOriginalQRCode() throws {
    let text = "GlyphPrint Test"
    let image = try QRGenerator().makeQRCode(from: text, targetWidth: 384)
    let raster = try MonochromeRasterizer().rasterize(image)
    let rows = try GlyphProtocol.makeRasterPackets(from: raster)
    // Reconstruct what the printer sees, independently interpreting its LSB-first wire format.
    var pixels: [UInt8] = []
    for row in rows {
        #expect(row.count == 56)
        for byte in row[6..<54] {
            for bit in 0..<8 { pixels.append(byte & (1 << bit) == 0 ? 255 : 0) }
        }
    }
    #expect(pixels.prefix(384 * 40).allSatisfy { $0 == 255 })
    #expect(pixels.suffix(384 * 40).allSatisfy { $0 == 255 })
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let reconstructed = try #require(CGImage(width: 384, height: 384, bitsPerComponent: 8,
        bitsPerPixel: 8, bytesPerRow: 384, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try VNImageRequestHandler(cgImage: reconstructed).perform([request])
    #expect(request.results?.first?.payloadStringValue == text)
}

@Test func qrRejectsCanvasTooSmallForWholeModules() {
    #expect(throws: GlyphPrintError.self) {
        try QRGenerator().makeQRCode(from: "GlyphPrint Test", targetWidth: 8)
    }
}
