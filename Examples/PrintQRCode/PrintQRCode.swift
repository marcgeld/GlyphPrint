import Foundation
import GlyphPrint

@main
struct PrintQRCodeExample {
    static func main() async {
        let text = CommandLine.arguments.dropFirst().joined(separator: " ")
        let printer = GlyphPrinter(config: PrinterConfig(
            advertisedNameSubstring: "Luxorp.PX10-1673",
            requiresNameMatch: true
        ))

        do {
            try await printer.connect(timeout: .seconds(20))
            try await printer.printQRCode(text.isEmpty ? "GlyphPrint Test" : text)

            // Give Bluetooth time to transmit before disconnecting.
            // This delay is not an acknowledgement from the printer.
            try await Task.sleep(for: .seconds(3))
            await printer.disconnect()
            print("The QR code has been sent to the printer.")
        } catch {
            await printer.disconnect()
            FileHandle.standardError.write(Data("Printing failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
