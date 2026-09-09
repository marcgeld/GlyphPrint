import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GlyphPrint

@main
struct PrintImageAndTextExample {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        var target: String?
        var preview: String?
        var brightness: Float = 0
        var contrast: Float = 1
        var index = 0
        while index < args.count {
            guard index + 1 < args.count else { throw GlyphPrintError.invalidArgument("Missing option value.") }
            let value = args[index + 1]
            switch args[index] {
            case "--printer": target = value
            case "--preview": preview = value
            case "--brightness":
                guard let number = Float(value), number.isFinite, (-1...1).contains(number) else {
                    throw GlyphPrintError.invalidArgument("Brightness must be -1...1.")
                }
                brightness = number
            case "--contrast":
                guard let number = Float(value), number.isFinite, (0...4).contains(number) else {
                    throw GlyphPrintError.invalidArgument("Contrast must be 0...4.")
                }
                contrast = number
            default: throw GlyphPrintError.invalidArgument("Unknown option: \(args[index])")
            }
            index += 2
        }
        guard let url = Bundle.module.url(
            forResource: "markus-winkler-Z8yWSsx8OWE-unsplash", withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768
              ] as CFDictionary) else { throw GlyphPrintError.invalidImage }

        let photo = try MonochromeRasterizer(mode: .floydSteinberg, brightness: brightness, contrast: contrast).rasterize(image)
        let creditImage = try TextRenderer(fontName: "Helvetica", fontSize: 22).render(
            "Photo by Markus Winkler\non Unsplash", alignment: .center)
        let credit = try MonochromeRasterizer().rasterize(creditImage)
        let page = try RasterImage.stacking([photo, credit], spacing: 12)

        if let preview {
            try savePreview(page, to: URL(fileURLWithPath: preview))
            print("Preview saved: \(preview) (\(page.width) × \(page.height) dots)")
            return
        }

        let selected = try target ?? PrinterPreferences().load()?.id.uuidString
        let config = try await PrinterSelection.configuration(for: selected)
        let printer = GlyphPrinter(config: config)
        do {
            try await printer.connect(timeout: .seconds(20))
            let result = try await printer.print(raster: page)
            await printer.disconnect()
            print("Result: \(result.rawValue)")
        } catch {
            await printer.disconnect()
            throw error
        }
    }

    /// Exports the exact final raster without accessing Bluetooth.
    static func savePreview(_ raster: RasterImage, to url: URL) throws {
        let pixels = raster.bytes.flatMap { byte in
            (0..<8).map { bit -> UInt8 in byte & (1 << (7 - bit)) == 0 ? 255 : 0 }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: raster.width, height: raster.height,
                bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: raster.width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw GlyphPrintError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GlyphPrintError.invalidImage }
    }
}
