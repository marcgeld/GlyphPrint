import Foundation
import CoreGraphics
import OSLog

public struct MonochromeRasterizer: Sendable {
    public enum Mode: Sendable {
        case threshold(UInt8)
    }

    public let targetWidth: Int
    public let mode: Mode

    private let logger = Logger.glyphPrintImage

    public init(targetWidth: Int = 384, mode: Mode = .threshold(160)) {
        self.targetWidth = targetWidth
        self.mode = mode
    }

    public func rasterize(_ image: CGImage) throws -> RasterImage {
        guard targetWidth % 8 == 0 else {
            throw GlyphPrintError.unsupportedImageWidth(targetWidth)
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
        let threshold: UInt8
        switch mode {
        case .threshold(let value):
            threshold = value
        }

        var bits = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let r = Float(pixels[index])
                let g = Float(pixels[index + 1])
                let b = Float(pixels[index + 2])
                let luminance = UInt8((0.299 * r + 0.587 * g + 0.114 * b).rounded())
                bits[y * width + x] = luminance < threshold ? 1 : 0
            }
        }
        return bits
    }
}
