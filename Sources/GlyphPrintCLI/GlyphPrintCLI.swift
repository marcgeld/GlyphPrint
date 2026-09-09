import Foundation
import GlyphPrint
import ImageIO

@main
struct GlyphPrintCLI {
    static func main() async {
        do { try await run(CLIOptions(Array(CommandLine.arguments.dropFirst()))) }
        catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run(_ options: CLIOptions) async throws {
        let preferences = PrinterPreferences()
        switch options.action {
        case .help: printUsage(); return
        case .showDefault:
            if let saved = try preferences.load() { print("\(saved.name ?? "Printer") — \(saved.id)") }
            else { print("No default printer saved.") }
            return
        case .clearDefault: try preferences.clear(); print("Default printer cleared."); return
        case .setDefault(let target):
            let devices = try await PrinterDiscovery.discoverPrinters(duration: .seconds(options.seconds), printersOnly: false)
            let selected = try PrinterSelection.select(from: devices, matching: target)
            let client = GlyphPrinterClient(config: selected.config)
            do { try await client.connect(); await client.disconnect() }
            catch { await client.disconnect(); throw error }
            try preferences.save(.init(id: selected.id, name: selected.name))
            print("Default saved: \(selected.name ?? "Printer") — \(selected.id)")
            return
        case .scan:
            let devices = try await PrinterDiscovery.discoverPrinters(duration: .seconds(options.seconds), printersOnly: options.printersOnly, verify: options.verify)
                .filter { device in options.name.map { device.name?.localizedCaseInsensitiveContains($0) == true } ?? true }
            if devices.isEmpty { print("No matching devices found.") }
            for device in devices {
                print("\(device.name ?? "unknown") — \(device.id)")
                print("  \(device.compatibility.rawValue); RSSI \(device.rssi == 127 ? "unavailable" : String(device.rssi)); advertised: \(device.advertisedServices.joined(separator: ", "))")
                if device.hasWeakSignal { print("  Warning: weak signal; explicit selection is still allowed.") }
                if let error = device.verificationError { print("  Verification: \(error)") }
            }
            return
        default: break
        }
        let explicit: String?
        if case .connect(let target) = options.action { explicit = target }
        else { explicit = options.printer }
        let target = try explicit ?? preferences.load()?.id.uuidString
        let config = try await PrinterSelection.configuration(for: target, duration: .seconds(options.seconds))
        let client = GlyphPrinterClient(config: config)
        let rasterizer = MonochromeRasterizer(mode: options.dither ? .floydSteinberg : .threshold(160),
            brightness: options.brightness, contrast: options.contrast)
        let printer = GlyphPrinter(config: config, transport: client, rasterizer: rasterizer)
        print("Connecting to \(config.targetPeripheralIdentifier?.uuidString ?? "printer")…")
        do {
            try await printer.connect()
            switch options.action {
            case .connect: print("Connected; write and notify channels verified.")
            case .status:
                let status = try await client.queryStatus()
                print("Device state (raw; flags not yet mapped): \(hex(status.payload))")
            case .image(let path):
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 4096
                      ] as CFDictionary) else { throw GlyphPrintError.invalidImage }
                print("Result: \(try await printer.print(image: image).rawValue)")
            case .printQR:
                let text = options.text.isEmpty ? "GlyphPrint Test" : options.text.joined(separator: " ")
                print("Result: \(try await printer.printQRCode(text).rawValue)")
            default: break
            }
            if let path = options.trace {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(await client.notifications()).write(to: URL(fileURLWithPath: path), options: .atomic)
                print("Notification trace saved: \(path)")
            }
            await printer.disconnect()
        } catch {
            await printer.disconnect()
            throw error
        }
    }

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func printUsage() {
        print("""
        Usage: gprint [--printer UUID|name] [text]
          --scan [--printers] [--name text] [--verify] [--seconds 1...60]
          --connect UUID|name           Verify transport without printing
          --status [--printer target]   Read raw device status
          --set-default UUID|name       Verify and save a default printer
          --show-default | --clear-default
          --image path [--dither] [--brightness -1...1] [--contrast 0...4]
          --trace path.json             Save received notifications
          --                            Treat remaining arguments as QR text
        Printer selection: --printer, saved UUID, then unambiguous discovery.
        Verified means GATT transport verified, not verified print quality.
        """)
    }
}
