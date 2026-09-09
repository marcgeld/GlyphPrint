import OSLog

extension Logger {
    // Use a safe subsystem; Bundle.main.bundleIdentifier can be nil in CLI/test contexts.
    private static let subsystem: String = {
        if let id = Bundle.main.bundleIdentifier, !id.isEmpty {
            return id
        }
        return "se.glyphprint"
    }()
    
    static let glyphPrint = Logger(subsystem: subsystem, category: "GlyphPrint")
    static let glyphPrintBLE = Logger(subsystem: subsystem, category: "BLE")
    static let glyphPrintProtocol = Logger(subsystem: subsystem, category: "Protocol")
    static let glyphPrintImage = Logger(subsystem: subsystem, category: "Image")
}
