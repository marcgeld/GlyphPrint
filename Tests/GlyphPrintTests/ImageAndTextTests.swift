import Testing
import Foundation
import CoreGraphics
import Vision
@testable import GlyphPrint

@Test func ditheringPreservesBlackAndWhite() {
    #expect(MonochromeRasterizer.dither(Array(repeating: 0, count: 64), width: 8, height: 8) == Array(repeating: 1, count: 64))
    #expect(MonochromeRasterizer.dither(Array(repeating: 255, count: 64), width: 8, height: 8) == Array(repeating: 0, count: 64))
}

@Test func ditheringPreservesAverageTone() {
    for tone: Float in [64, 128, 192] {
        let bits = MonochromeRasterizer.dither(Array(repeating: tone, count: 4096), width: 64, height: 64)
        let blackFraction = Float(bits.reduce(0) { $0 + Int($1) }) / 4096
        #expect(abs(blackFraction - (1 - tone / 255)) < 0.03)
    }
}

@Test func diffusionRespectsImageEdges() {
    #expect(MonochromeRasterizer.dither([128, 128, 128, 128], width: 1, height: 4) == [0, 1, 0, 1])
    #expect(MonochromeRasterizer.dither([128, 128, 128, 128], width: 2, height: 2) == [0, 1, 1, 0])
}

@Test func stackingPreservesSectionOrderAndWhiteSpacing() throws {
    let first = RasterImage(width: 8, height: 2, bytes: Data([0x80, 0x01]))
    let second = RasterImage(width: 8, height: 1, bytes: Data([0xAA]))
    let combined = try RasterImage.stacking([first, second], spacing: 2)
    #expect(combined == RasterImage(width: 8, height: 5, bytes: Data([0x80, 0x01, 0, 0, 0xAA])))
    #expect(try GlyphProtocol.makeRasterPackets(from: combined).count == 5)
}

@Test func stackingRejectsMalformedSections() {
    let valid = RasterImage(width: 8, height: 1, bytes: Data([0]))
    for sections in [[], [valid, RasterImage(width: 16, height: 1, bytes: Data([0, 0]))],
                     [RasterImage(width: 8, height: 2, bytes: Data([0]))]] {
        #expect(throws: GlyphPrintError.self) { try RasterImage.stacking(sections) }
    }
    #expect(throws: GlyphPrintError.self) { try RasterImage.stacking([valid], spacing: -1) }
    #expect(throws: GlyphPrintError.self) { try RasterImage.stacking([valid, valid], spacing: 65_536) }
}

@Test func renderedCreditRemainsReadableAfterRasterization() throws {
    let renderer = TextRenderer(fontName: "Helvetica", fontSize: 22)
    let image = try renderer.render("Photo by Markus Winkler\non Unsplash", alignment: .center)
    let raster = try MonochromeRasterizer().rasterize(image)
    let pixels = raster.bytes.flatMap { byte in
        (0..<8).map { bit -> UInt8 in byte & (1 << (7 - bit)) == 0 ? 255 : 0 }
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let printed = try #require(CGImage(width: raster.width, height: raster.height,
        bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: raster.width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    try VNImageRequestHandler(cgImage: printed).perform([request])
    let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    #expect(recognized.contains("Photo by Markus Winkler"))
    #expect(recognized.contains("on Unsplash"))
}

@Test func textWrapsAndHonorsFontSize() throws {
    let text = "Photo by Markus Winkler on Unsplash"
    let renderer = TextRenderer(fontName: "Helvetica", fontSize: 22)
    let wide = try renderer.render(text, width: 384)
    let narrow = try renderer.render(text, width: 160)
    #expect(narrow.height > wide.height)
    let larger = try TextRenderer(fontName: "Helvetica", fontSize: 32).render(text, width: 384)
    #expect(larger.height > wide.height)
    #expect(throws: GlyphPrintError.self) { try renderer.render(text, width: 16, padding: 12) }
    #expect(throws: GlyphPrintError.self) { try TextRenderer(fontSize: .nan).render(text) }
}
