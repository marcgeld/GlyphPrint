import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

public struct QRGenerator: Sendable {
    public init() {}

    /// Centers whole QR modules on the printer canvas with at least four white modules around them.
    public func makeQRCode(from string: String, targetWidth: Int) throws -> CGImage {
        guard targetWidth > 0, targetWidth % 8 == 0 else {
            throw GlyphPrintError.unsupportedImageWidth(targetWidth)
        }
        let modules = try makeQRCode(from: string, scale: 1)
        let pixelsPerModule = targetWidth / (modules.width + 8)
        guard pixelsPerModule >= 1 else { throw GlyphPrintError.invalidImage }
        guard let context = CGContext(
            data: nil, width: targetWidth, height: targetWidth,
            bitsPerComponent: 8, bytesPerRow: targetWidth,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw GlyphPrintError.invalidImage }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetWidth))
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        let size = modules.width * pixelsPerModule
        let offset = (targetWidth - size) / 2
        context.draw(modules, in: CGRect(x: offset, y: offset, width: size, height: size))
        guard let image = context.makeImage() else { throw GlyphPrintError.invalidImage }
        return image
    }

    public func makeQRCode(from string: String, scale: CGFloat = 10) throws -> CGImage {
        guard scale.isFinite, scale > 0 else { throw GlyphPrintError.invalidImage }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            throw GlyphPrintError.invalidImage
        }

        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            throw GlyphPrintError.invalidImage
        }
        return cgImage
    }
}
