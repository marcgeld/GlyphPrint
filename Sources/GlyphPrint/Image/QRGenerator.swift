import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

public struct QRGenerator: Sendable {
    public init() {}

    public func makeQRCode(from string: String, scale: CGFloat = 10) throws -> CGImage {
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
