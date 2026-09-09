import Foundation
import GlyphPrint
import ImageIO
import CoreGraphics
import OSLog

// Safe CLI logger (optional, used if needed for additional logs)
extension Logger {
    private static let cliSubsystem: String = {
        if let id = Bundle.main.bundleIdentifier, !id.isEmpty {
            return id
        }
        return "se.glyphprint.cli"
    }()
    static let glyphPrintCli = Logger(subsystem: cliSubsystem, category: "GlyphPrintCli")
}

@main
struct GlyphPrintCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        do {
            let printer = GlyphPrinter()

            if args.isEmpty {
                print("No arguments — printing test QR code…")
                try await connectAndPrint(printer: printer) {
                    try await printer.printQRCode("GlyphPrint Test")
                }
            } else if args.first == "--image" {
                guard args.count >= 2 else {
                    fputs("Error: --image requires a file path\n", stderr)
                    printUsage()
                    exit(1)
                }
                let path = args[1]
                let image = try loadImage(at: path)
                print("Printing image \(path)…")
                try await connectAndPrint(printer: printer) {
                    try await printer.print(image: image)
                }
            } else if args.first == "--help" || args.first == "-h" {
                printUsage()
            } else {
                let text = args.joined(separator: " ")
                print("Printing QR code for \"\(text)\"…")
                try await connectAndPrint(printer: printer) {
                    try await printer.printQRCode(text)
                }
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func connectAndPrint(printer: GlyphPrinter, _ work: @Sendable @escaping () async throws -> Void
    ) async throws {
        print("Connecting to printer…")
        try await printer.connect()
        defer { printer.disconnect() }
        try await work()
        print("Done.")
    }

    private static func loadImage(at path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GlyphPrintError.invalidImage
        }
        return image
    }

    private static func printUsage() {
        print("""
        Usage: glyphprint [options] [text]

        Options:
          (no arguments)        Print a test QR code
          <text>                Print text as a QR code
          --image <path>        Print an image file (PNG, JPEG, etc.)
          --help, -h            Show this help message
        """)
    }
}
