import Foundation
import CoreBluetooth

public enum PrinterDiscovery {
    /// Verification connects and enables notifications, but sends no print data.
    /// A verified device supports the transport; physical print quality remains unverified.
    public static func discoverPrinters(duration: Duration = .seconds(5), printersOnly: Bool = true,
                                        verify: Bool = false) async throws -> [DiscoveredPrinter] {
        guard duration > .zero, duration <= .seconds(60) else {
            throw GlyphPrintError.invalidArgument("Scan duration must be greater than zero and at most 60 seconds.")
        }
        var devices = try await DiscoverySession().scan(duration: duration)
        if printersOnly { devices.removeAll { $0.profile == nil } }
        if verify {
            for index in devices.indices where devices[index].profile != nil {
                try Task.checkCancellation()
                let client = GlyphPrinterClient(config: devices[index].config)
                do {
                    try await client.connect(timeout: .seconds(8))
                    devices[index].compatibility = .verified
                    await client.disconnect()
                } catch {
                    await client.disconnect()
                    try Task.checkCancellation()
                    devices[index].compatibility = .unverified
                    devices[index].verificationError = error.localizedDescription
                }
            }
        }
        return devices
    }
}

private final class DiscoverySession: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "GlyphPrint.Discovery")
    private var central: CBCentralManager!
    private let operation = BLEOperation()
    private var devices: [UUID: DiscoveredPrinter] = [:]
    private var duration: Duration = .seconds(5)
    private var started = false

    func scan(duration: Duration) async throws -> [DiscoveredPrinter] {
        try await operation.wait(timeout: duration + .seconds(5), operationName: "BLE scan") {
            self.queue.async {
                guard !self.operation.isFinished else { return }
                self.duration = duration
                self.central = CBCentralManager(delegate: self, queue: self.queue)
            }
        } cancel: {
            self.queue.async { self.central?.stopScan() }
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.devices.values.sorted {
                    let lhs = $0.rssi == 127 ? -128 : $0.rssi
                    let rhs = $1.rssi == 127 ? -128 : $1.rssi
                    return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs > rhs
                })
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !operation.isFinished else { return }
        switch central.state {
        case .poweredOn:
            guard !started else { return }
            started = true
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            queue.asyncAfter(deadline: .now() + seconds) {
                self.central.stopScan()
                self.operation.finish(.success(()))
            }
        case .unknown, .resetting: break
        default:
            central.stopScan()
            operation.finish(.failure(GlyphPrintError.bluetoothUnavailable))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !operation.isFinished else { return }
        let old = devices[peripheral.identifier]
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? old?.name
        let advertised = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []).map(\.uuidString)
        let services = Array(Set((old?.advertisedServices ?? []) + advertised)).sorted()
        let rssi = RSSI.intValue == 127 ? (old?.rssi ?? 127) : RSSI.intValue
        devices[peripheral.identifier] = DiscoveredPrinter(id: peripheral.identifier, name: name, rssi: rssi, advertisedServices: services)
    }
}
