import Foundation
import GlyphPrint
import ImageIO
import CoreGraphics
import CoreBluetooth
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
            if args.isEmpty {
                let printer = GlyphPrinter()
                print("No arguments — printing test QR code…")
                try await connectAndPrint(printer: printer) {
                    try await printer.printQRCode("GlyphPrint Test")
                }
            } else if args.first == "--scan" || args.first == "scan" {
                let duration = scanDuration(from: args)
                let filter = deviceFilter(from: args)
                try await scanDevices(duration: duration, filter: filter)
            } else if args.first == "--connect" || args.first == "connect" {
                guard args.count >= 2 else {
                    fputs("Error: --connect requires a device UUID or name substring\n", stderr)
                    printUsage()
                    exit(1)
                }
                try await connectToDevice(matching: args[1])
            } else if args.first == "--image" {
                guard args.count >= 2 else {
                    fputs("Error: --image requires a file path\n", stderr)
                    printUsage()
                    exit(1)
                }
                let path = args[1]
                let image = try loadImage(at: path)
                let printer = GlyphPrinter()
                print("Printing image \(path)…")
                try await connectAndPrint(printer: printer) {
                    try await printer.print(image: image)
                }
            } else if args.first == "--help" || args.first == "-h" {
                printUsage()
            } else {
                let text = args.joined(separator: " ")
                let printer = GlyphPrinter()
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

    private static func scanDevices(duration: Duration, filter: DeviceFilter) async throws {
        print("Scanning for BLE devices...")
        let allDevices = try await BLEDeviceScanner().scan(duration: duration)
        let devices = allDevices.filter { filter.includes($0) }

        guard !devices.isEmpty else {
            if filter.isEmpty {
                print("No BLE devices found.")
            } else {
                print("No matching BLE devices found.")
            }
            return
        }

        for (index, device) in devices.enumerated() {
            let name = device.name ?? "unknown"
            let services = device.serviceUUIDs.isEmpty ? "-" : device.serviceUUIDs.joined(separator: ",")
            print("\(index + 1). \(name)")
            print("   id: \(device.identifier.uuidString)")
            print("   rssi: \(device.rssi)")
            print("   services: \(services)")
        }
    }

    private static func connectToDevice(matching target: String) async throws {
        let config: PrinterConfig
        if let identifier = UUID(uuidString: target) {
            config = PrinterConfig(advertisedNameSubstring: nil, targetPeripheralIdentifier: identifier)
            print("Connecting to \(identifier.uuidString)...")
        } else {
            config = PrinterConfig(advertisedNameSubstring: target, requiresNameMatch: true)
            print("Connecting to device matching \"\(target)\"...")
        }

        let printer = GlyphPrinter(config: config)
        try await printer.connect()
        print("Connected.")
        await printer.disconnect()
        print("Disconnected.")
    }

    private static func connectAndPrint(printer: GlyphPrinter, _ work: @Sendable @escaping () async throws -> Void
    ) async throws {
        print("Connecting to printer…")
        try await printer.connect()
        do {
            try await work()
        } catch {
            await printer.disconnect()
            throw error
        }
        await printer.disconnect()
        print("Done.")
    }

    private static func scanDuration(from args: [String]) -> Duration {
        guard let secondsIndex = args.firstIndex(of: "--seconds"),
              args.indices.contains(secondsIndex + 1),
              let seconds = Double(args[secondsIndex + 1]) else {
            return .seconds(5)
        }
        return .milliseconds(Int(seconds * 1000))
    }

    private static func deviceFilter(from args: [String]) -> DeviceFilter {
        DeviceFilter(
            printerConfig: args.contains("--printers") || args.contains("--printer") ? .default : nil,
            nameSubstring: value(after: "--name", in: args)
        )
    }

    private static func value(after option: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: option),
              args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
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
        Usage: gprint [options] [text]

        Options:
          (no arguments)        Print a test QR code
          <text>                Print text as a QR code
          --scan                Scan nearby BLE devices
          --scan --seconds <n>  Scan for n seconds
          --scan --printers     Show likely BLE printers only
          --scan --name <text>  Show devices whose name contains text
          --connect <id|name>   Connect to a BLE printer by UUID or name substring
          --image <path>        Print an image file (PNG, JPEG, etc.)
          --help, -h            Show this help message
        """)
    }
}

private struct BLEDevice: Sendable {
    let identifier: UUID
    let name: String?
    let rssi: Int
    let serviceUUIDs: [String]
}

private struct DeviceFilter: Equatable {
    let printerConfig: PrinterConfig?
    let nameSubstring: String?

    func includes(_ device: BLEDevice) -> Bool {
        if let printerConfig, !device.matchesPrinter(config: printerConfig) {
            return false
        }

        if let nameSubstring, !nameSubstring.isEmpty {
            return device.name?.localizedCaseInsensitiveContains(nameSubstring) == true
        }

        return true
    }

    var isEmpty: Bool {
        printerConfig == nil && (nameSubstring?.isEmpty ?? true)
    }
}

private extension BLEDevice {
    func matchesPrinter(config: PrinterConfig) -> Bool {
        let serviceMatches = serviceUUIDs.contains { $0.caseInsensitiveCompare(config.serviceUUID) == .orderedSame }
        let nameMatches: Bool
        if let advertisedNameSubstring = config.advertisedNameSubstring, !advertisedNameSubstring.isEmpty {
            nameMatches = name?.localizedCaseInsensitiveContains(advertisedNameSubstring) == true
        } else {
            nameMatches = false
        }
        return serviceMatches || nameMatches
    }
}

private final class BLEDeviceScanner: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "GlyphPrint.CLI.BLEScanner")

    private var central: CBCentralManager!
    private var devices: [UUID: BLEDevice] = [:]
    private var continuation: CheckedContinuation<[BLEDevice], Error>?
    private var isScanning = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    func scan(duration: Duration) async throws -> [BLEDevice] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.continuation == nil else {
                    continuation.resume(
                        throwing: GlyphPrintError.connectionFailed("A scan operation is already in progress.")
                    )
                    return
                }

                self.devices.removeAll()
                self.continuation = continuation
                self.startScanIfPossible()

                self.queue.asyncAfter(deadline: .now() + duration.timeInterval) {
                    self.finishScan()
                }
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        startScanIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? localName
        devices[peripheral.identifier] = BLEDevice(
            identifier: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            serviceUUIDs: serviceUUIDs.map(\.uuidString).sorted()
        )
    }

    private func startScanIfPossible() {
        guard continuation != nil, !isScanning else { return }

        switch central.state {
        case .poweredOn:
            isScanning = true
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .unsupported, .unauthorized, .poweredOff:
            finishScan(throwing: GlyphPrintError.bluetoothUnavailable)
        case .unknown, .resetting:
            return
        @unknown default:
            finishScan(throwing: GlyphPrintError.bluetoothUnavailable)
        }
    }

    private func finishScan(throwing error: Error? = nil) {
        if isScanning {
            central.stopScan()
            isScanning = false
        }

        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else {
            let sorted = devices.values.sorted { first, second in
                if first.rssi == second.rssi {
                    return first.identifier.uuidString < second.identifier.uuidString
                }
                return first.rssi > second.rssi
            }
            continuation.resume(returning: sorted)
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
