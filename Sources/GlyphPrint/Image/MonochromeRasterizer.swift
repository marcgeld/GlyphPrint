import Foundation
import CoreGraphics
import OSLog

public struct MonochromeRasterizer: Sendable {
    public enum Mode: Sendable {
        case threshold(UInt8)
        /// Floyd–Steinberg error diffusion for photographs and other continuous tones.
        case floydSteinberg
    }

    public let targetWidth: Int
    public let mode: Mode
    public let brightness: Float
    public let contrast: Float

    private let logger = Logger.glyphPrintImage

    public init(targetWidth: Int = 384, mode: Mode = .threshold(160), brightness: Float = 0, contrast: Float = 1) {
        self.targetWidth = targetWidth
        self.mode = mode
        self.brightness = brightness
        self.contrast = contrast
    }

    public func rasterize(_ image: CGImage) throws -> RasterImage {
        guard targetWidth > 0, targetWidth % 8 == 0 else {
            throw GlyphPrintError.unsupportedImageWidth(targetWidth)
        }

        guard brightness.isFinite, (-1...1).contains(brightness), contrast.isFinite, (0...4).contains(contrast) else {
            throw GlyphPrintError.invalidArgument("Brightness must be -1...1 and contrast 0...4.")
        }
        let resized = try resize(image, targetWidth: targetWidth)
        let pixels = try rgbaPixels(from: resized)
        let width = resized.width
        let height = resized.height
        let monochrome = makeMonochromeBits(fromRGBA: pixels, width: width, height: height)
        let packed = Self.packBits(monochrome, width: width, height: height)
        logger.debug("Rasterized image to \(width, privacy: .public)x\(height, privacy: .public)")
        return RasterImage(width: width, height: height, bytes: packed)
    }

    static func packBits(_ bits: [UInt8], width: Int, height: Int) -> Data {
        let bytesPerRow = width / 8
        var packed = Data(capacity: bytesPerRow * height)

        for row in 0..<height {
            for byteIndex in 0..<bytesPerRow {
                var output: UInt8 = 0
                for bit in 0..<8 {
                    let x = byteIndex * 8 + bit
                    let index = row * width + x
                    output |= (bits[index] & 0x01) << (7 - bit)
                }
                packed.append(output)
            }
        }

        return packed
    }

    private func resize(_ image: CGImage, targetWidth: Int) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw GlyphPrintError.invalidImage
        }

        let scale = CGFloat(targetWidth) / CGFloat(width)
        let targetHeight = max(1, Int((CGFloat(height) * scale).rounded(.toNearestOrAwayFromZero)))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw GlyphPrintError.invalidImage
        }
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw GlyphPrintError.invalidImage
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let output = context.makeImage() else {
            throw GlyphPrintError.invalidImage
        }
        return output
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw GlyphPrintError.invalidImage
        }
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw GlyphPrintError.invalidImage
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func makeMonochromeBits(fromRGBA pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        let luminance: [Float] = stride(from: 0, to: pixels.count, by: 4).map { index -> Float in
            let red = Float(pixels[index]) * 0.299
            let green = Float(pixels[index + 1]) * 0.587
            let blue = Float(pixels[index + 2]) * 0.114
            return Self.adjust(red + green + blue, brightness: brightness, contrast: contrast)
        }
        switch mode {
        case .threshold(let threshold):
            return luminance.map { UInt8($0.rounded()) < threshold ? 1 : 0 }
        case .floydSteinberg:
            return Self.dither(luminance, width: width, height: height)
        }
    }

    static func adjust(_ luminance: Float, brightness: Float, contrast: Float) -> Float {
        min(255, max(0, (luminance - 127.5) * contrast + 127.5 + brightness * 255))
    }

    static func dither(_ luminance: [Float], width: Int, height: Int) -> [UInt8] {
        var values = luminance
        var bits = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let black = values[index] < 128
                bits[index] = black ? 1 : 0
                let error = values[index] - (black ? 0 : 255)
                if x + 1 < width { values[index + 1] += error * 7 / 16 }
                if y + 1 < height {
                    if x > 0 { values[index + width - 1] += error * 3 / 16 }
                    values[index + width] += error * 5 / 16
                    if x + 1 < width { values[index + width + 1] += error / 16 }
                }
            }
        }
        return bits
    }
}
