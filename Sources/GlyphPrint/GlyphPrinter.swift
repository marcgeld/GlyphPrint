import Foundation
import CoreGraphics
import OSLog

public final class GlyphPrinter: Sendable {
    private let transport: any GlyphPrinterTransport
    private let jobs = PrintJobQueue()
    private let qrGenerator: QRGenerator
    private let rasterizer: MonochromeRasterizer

    public init(
        config: PrinterConfig = .default,
        transport: (any GlyphPrinterTransport)? = nil,
        qrGenerator: QRGenerator = QRGenerator(),
        rasterizer: MonochromeRasterizer? = nil
    ) {
        self.transport = transport ?? GlyphPrinterClient(config: config)
        self.qrGenerator = qrGenerator
        self.rasterizer = rasterizer ?? MonochromeRasterizer(targetWidth: config.imageWidth)
    }

    public func connect(timeout: Duration = .seconds(30)) async throws {
        Logger.glyphPrint.debug("Connect with timeout: \(timeout)")
        try await transport.connect(timeout: timeout)
    }

    public func disconnect() async {
        await transport.disconnect()
    }

    public func printQRCode(_ string: String) async throws {
        let image = try qrGenerator.makeQRCode(from: string, targetWidth: rasterizer.targetWidth)
        try await print(image: image)
    }

    public func print(image: CGImage) async throws {
        let raster = try rasterizer.rasterize(image)
        try await print(raster: raster)
    }

    /// Sends pre-rasterized content without scaling or dithering it again.
    public func print(raster: RasterImage) async throws {
        let packets = try GlyphProtocol.buildPrintJob(from: raster)
        try await jobs.send(packets, using: transport)
    }

    public func makePacketsForQRCode(_ string: String) throws -> [Data] {
        let image = try qrGenerator.makeQRCode(from: string, targetWidth: rasterizer.targetWidth)
        return try makePackets(for: image)
    }

    public func makePackets(for image: CGImage) throws -> [Data] {
        let raster = try rasterizer.rasterize(image)
        return try GlyphProtocol.buildPrintJob(from: raster)
    }
}

