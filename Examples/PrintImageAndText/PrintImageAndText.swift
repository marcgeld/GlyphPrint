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
        guard args.isEmpty || (args.count == 2 && args[0] == "--preview") else {
            print("Usage: photo-example [--preview output.png]")
            exit(1)
        }
        guard let url = Bundle.module.url(
            forResource: "markus-winkler-Z8yWSsx8OWE-unsplash", withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768
              ] as CFDictionary) else { throw GlyphPrintError.invalidImage }

        let photo = try MonochromeRasterizer(mode: .floydSteinberg).rasterize(image)
        let creditImage = try TextRenderer(fontName: "Helvetica", fontSize: 22).render(
            "Photo by Markus Winkler\non Unsplash", alignment: .center)
        let credit = try MonochromeRasterizer().rasterize(creditImage)
        let page = try RasterImage.stacking([photo, credit], spacing: 12)

        if !args.isEmpty {
            try savePreview(page, to: URL(fileURLWithPath: args[1]))
            print("Preview saved: \(args[1]) (\(page.width) × \(page.height) dots)")
            return
        }

        let printer = GlyphPrinter(config: PrinterConfig(
            advertisedNameSubstring: "Luxorp.PX10-1673", requiresNameMatch: true))
        do {
            try await printer.connect(timeout: .seconds(20))
            try await printer.print(raster: page)
            // Allow Bluetooth to drain; this is not a printer acknowledgement.
            try await Task.sleep(for: .seconds(3))
            await printer.disconnect()
            print("The photo and credit have been sent to the printer.")
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
