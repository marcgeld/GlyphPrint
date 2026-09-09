import Foundation
import CoreGraphics
import OSLog

public final class GlyphPrinter: Sendable {
    private let transport: any GlyphPrinterTransport
    private let config: PrinterConfig
    private let qrGenerator: QRGenerator
    private let rasterizer: MonochromeRasterizer
    private let logger = Logger.glyphPrint

    public init(
        config: PrinterConfig = .default,
        transport: (any GlyphPrinterTransport)? = nil,
        qrGenerator: QRGenerator = QRGenerator(),
        rasterizer: MonochromeRasterizer? = nil
    ) {
        self.config = config
        self.transport = transport ?? GlyphPrinterClient(config: config)
        self.qrGenerator = qrGenerator
        self.rasterizer = rasterizer ?? MonochromeRasterizer(targetWidth: config.imageWidth)
    }

    public func connect(timeout: Duration = .seconds(15)) async throws {
        Logger.glyphPrint.debug("Connect with timeout: \(timeout)")
        try await transport.connect(timeout: timeout)
    }

    public func disconnect() {
        transport.disconnect()
    }

    public func printQRCode(_ string: String) async throws {
        let image = try qrGenerator.makeQRCode(from: string)
        try await print(image: image)
    }

    public func print(image: CGImage) async throws {
        let raster = try rasterizer.rasterize(image)
        let packets = try GlyphProtocol.buildPrintJob(from: raster)
        for packet in packets {
            try await transport.send(packet)
        }
    }

    public func makePacketsForQRCode(_ string: String) throws -> [Data] {
        let image = try qrGenerator.makeQRCode(from: string)
        return try makePackets(for: image)
    }

    public func makePackets(for image: CGImage) throws -> [Data] {
        let raster = try rasterizer.rasterize(image)
        return try GlyphProtocol.buildPrintJob(from: raster)
    }
}

