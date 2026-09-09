import Foundation

public struct RasterImage: Sendable, Hashable {
    public let width: Int
    public let height: Int
    /// Row-major bitmap: bit 7 is the leftmost pixel; 1 means black.
    public let bytes: Data

    public init(width: Int, height: Int, bytes: Data) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }
}

extension RasterImage {
    /// Combines already rasterized sections in top-to-bottom order without changing their pixels.
    public static func stacking(_ sections: [RasterImage], spacing: Int = 0) throws -> RasterImage {
        guard let first = sections.first, first.width > 0, first.width % 8 == 0,
              first.width / 8 <= Int(UInt16.max) - 2, spacing >= 0, spacing <= 65_536 else {
            throw GlyphPrintError.invalidImage
        }
        let rowBytes = first.width / 8
        var height = 0
        var bytes = Data()
        for (index, section) in sections.enumerated() {
            guard section.width == first.width, section.height > 0, section.height <= 65_536,
                  section.bytes.count == section.height * rowBytes else { throw GlyphPrintError.invalidImage }
            let gap = index == 0 ? 0 : spacing
            guard height + gap + section.height <= 65_536 else { throw GlyphPrintError.invalidImage }
            bytes.append(Data(repeating: 0, count: gap * rowBytes))
            bytes.append(section.bytes)
            height += gap + section.height
        }
        return RasterImage(width: first.width, height: height, bytes: bytes)
    }
}
