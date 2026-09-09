import Foundation
import GlyphPrint

@main
struct PrintQRCodeExample {
    static func main() async {
        var printer: GlyphPrinter?
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            var target = try PrinterPreferences().load()?.id.uuidString
            if let index = args.firstIndex(of: "--printer") {
                guard index + 1 < args.count else { throw GlyphPrintError.invalidArgument("--printer requires a UUID or name.") }
                target = args[index + 1]
                args.removeSubrange(index...index + 1)
            }
            let config = try await PrinterSelection.configuration(for: target)
            let connectedPrinter = GlyphPrinter(config: config)
            printer = connectedPrinter
            let text = args.joined(separator: " ")
            try await connectedPrinter.connect(timeout: .seconds(20))
            let result = try await connectedPrinter.printQRCode(text.isEmpty ? "GlyphPrint Test" : text)
            await connectedPrinter.disconnect()
            print("Result: \(result.rawValue)")
        } catch {
            await printer?.disconnect()
            FileHandle.standardError.write(Data("Printing failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
