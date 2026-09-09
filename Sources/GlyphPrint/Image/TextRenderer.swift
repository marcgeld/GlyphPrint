import Foundation
import CoreGraphics
import CoreText

/// Renders wrapped black text on white using fonts available on iOS or macOS.
public struct TextRenderer: Sendable {
    public enum Alignment: Sendable {
        case left, center, right
    }

    public let fontName: String
    /// Font size in printer pixels, not screen-scaled points.
    public let fontSize: CGFloat

    public init(fontName: String = "Helvetica", fontSize: CGFloat = 22) {
        self.fontName = fontName
        self.fontSize = fontSize
    }

    /// Missing fonts are substituted by Core Text. Register custom fonts in the host app.
    public func render(
        _ text: String, width: Int = 384, padding: Int = 12, alignment: Alignment = .left
    ) throws -> CGImage {
        guard width > 0, padding >= 0, padding < width / 2,
              fontSize.isFinite, fontSize > 0, !text.isEmpty else {
            throw GlyphPrintError.invalidImage
        }
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        var ctAlignment: CTTextAlignment
        switch alignment {
        case .left: ctAlignment = .left
        case .center: ctAlignment = .center
        case .right: ctAlignment = .right
        }
        let paragraph = withUnsafePointer(to: &ctAlignment) { pointer in
            var setting = CTParagraphStyleSetting(
                spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let contentWidth = CGFloat(width - 2 * padding)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: contentWidth, height: .greatestFiniteMagnitude), nil)
        let measuredHeight = ceil(size.height) + CGFloat(padding) * 2 + 2
        guard measuredHeight.isFinite, measuredHeight > 0, measuredHeight <= 65_536 else {
            throw GlyphPrintError.invalidImage
        }
        let height = Int(measuredHeight)
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw GlyphPrintError.invalidImage }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.textMatrix = .identity
        let path = CGPath(rect: CGRect(x: padding, y: padding,
            width: width - 2 * padding, height: height - 2 * padding), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard CTFrameGetVisibleStringRange(frame).length == attributed.length else {
            throw GlyphPrintError.invalidImage
        }
        CTFrameDraw(frame, context)
        guard let image = context.makeImage() else { throw GlyphPrintError.invalidImage }
        return image
    }
}
