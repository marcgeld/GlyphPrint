import Foundation

public struct RasterImage: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public let bytes: Data

    public init(width: Int, height: Int, bytes: Data) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }
}
