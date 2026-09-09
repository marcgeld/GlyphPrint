import Foundation

/// Shared by the CLI and examples. Nothing is saved unless save() is explicitly called.
public struct PrinterPreferences: Sendable {
    public struct SavedPrinter: Sendable, Codable, Equatable {
        public let id: UUID
        public let name: String?
        public init(id: UUID, name: String?) { self.id = id; self.name = name }
    }
    public let url: URL
    public init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GlyphPrint/default-printer.json")) { self.url = url }

    public func load() throws -> SavedPrinter? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SavedPrinter.self, from: Data(contentsOf: url))
    }
    public func save(_ printer: SavedPrinter) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(printer).write(to: url, options: .atomic)
    }
    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
