import Foundation
import CoreBluetooth
import OSLog

extension CBManagerState {
    var logDescription: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

public protocol GlyphPrinterTransport: Sendable {
    func connect(timeout: Duration) async throws
    func disconnect()
    func send(_ data: Data) async throws
}

public final class GlyphPrinterClient: NSObject, @unchecked Sendable, GlyphPrinterTransport {
    private let config: PrinterConfig
    private let queue: DispatchQueue
    private let logger = Logger.glyphPrintBLE

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var sendContinuation: CheckedContinuation<Void, Error>?
    private var pendingChunks: [Data] = []
    private var notifyReady = false
    private var isScanning = false

    public init(config: PrinterConfig = .default, queue: DispatchQueue? = nil) {
        self.config = config
        self.queue = queue ?? DispatchQueue(label: "GlyphPrint.BLE")
        super.init()
        self.central = CBCentralManager(delegate: self, queue: self.queue)
    }

    public func connect(timeout: Duration = .seconds(30)) async throws {
        logger.debug("connect(timeout: \(timeout.components.seconds, privacy: .public)s) called")
        if let peripheral, peripheral.state == .connected, notifyReady, writeCharacteristic != nil {
            return
        }
        
        logger.debug("Beginning BLE connect flow with timeout \(timeout.components.seconds, privacy: .public)s")

        try await withTimeout(timeout, operation: "BLE connect") {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.queue.async {
                    self.connectContinuation = continuation
                    self.logger.debug("Connect continuation set. Attempting to start scan if possible. Current central state: \(String(describing: self.central.state.rawValue), privacy: .public)")
                    self.scanStateUpdate()
                }
            }
        }
    }

    public func disconnect() {
        queue.async {
            if let peripheral = self.peripheral {
                self.central.cancelPeripheralConnection(peripheral)
            }
            self.pendingChunks.removeAll()
            self.writeCharacteristic = nil
            self.notifyCharacteristic = nil
            self.notifyReady = false
        }
    }

    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.notifyReady else {
                    continuation.resume(throwing: GlyphPrintError.connectionFailed("Notify channel is not ready."))
                    return
                }
                guard let peripheral = self.peripheral, peripheral.state == .connected else {
                    continuation.resume(throwing: GlyphPrintError.connectionFailed("Peripheral is not connected."))
                    return
                }
                guard let characteristic = self.writeCharacteristic else {
                    continuation.resume(throwing: GlyphPrintError.missingWriteCharacteristic)
                    return
                }

                let maxLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
                self.logger.debug("Queueing \(data.count, privacy: .public) bytes using max chunk \(maxLength, privacy: .public)")

                if maxLength <= 0 {
                    continuation.resume(throwing: GlyphPrintError.sendFailed("maximumWriteValueLength returned 0"))
                    return
                }

                self.sendContinuation = continuation
                self.pendingChunks.append(contentsOf: Self.chunk(data: data, chunkSize: maxLength))
                self.flushQueue(peripheral: peripheral, characteristic: characteristic)
            }
        }
    }

    private func scanStateUpdate() {
        logger.debug("Central state: \(self.central.state.logDescription, privacy: .public)")
        switch central.state {
        case .poweredOn:
            guard !isScanning else { return }
            isScanning = true
            let serviceUUID = CBUUID(string: config.serviceUUID)
            logger.debug("Starting BLE scan for service \(self.config.serviceUUID, privacy: .public)")
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        case .unsupported:
            logger.error("Bluetooth unsupported on this device")
            failConnect(with: GlyphPrintError.bluetoothUnavailable)
        case .unauthorized:
            logger.error("Bluetooth unauthorized. Check Info.plist usage descriptions and entitlements.")
            failConnect(with: GlyphPrintError.bluetoothUnavailable)
        case .poweredOff:
            logger.error("Bluetooth is powered off. Ask user to enable Bluetooth.")
            failConnect(with: GlyphPrintError.bluetoothUnavailable)
        case .resetting:
            logger.debug("Bluetooth is resetting. Waiting for state update...")
            // Do not fail here; centralManagerDidUpdateState will be called again.
            return
        case .unknown:
            logger.debug("Bluetooth state unknown. Waiting for state update...")
            // Do not fail here; centralManagerDidUpdateState will be called again.
            return
        @unknown default:
            logger.error("Bluetooth state unrecognized")
            failConnect(with: GlyphPrintError.bluetoothUnavailable)
        }
    }

    private func flushQueue(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        logger.debug("Flushing write queue. Pending chunks: \(self.pendingChunks.count, privacy: .public)")
        while peripheral.canSendWriteWithoutResponse, !pendingChunks.isEmpty {
            let chunk = pendingChunks.removeFirst()
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            logger.debug("Sent chunk \(chunk.count, privacy: .public) bytes")
        }

        if pendingChunks.isEmpty, let sendContinuation {
            self.sendContinuation = nil
            sendContinuation.resume()
        }
    }

    private func failConnect(with error: Error) {
        isScanning = false
        if let continuation = connectContinuation {
            connectContinuation = nil
            continuation.resume(throwing: error)
        }
    }

    private static func chunk(data: Data, chunkSize: Int) -> [Data] {
        guard chunkSize > 0 else { return [] }
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: String,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await body()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                self.logger.error("Operation \(operation, privacy: .public) timed out after \(duration.components.seconds, privacy: .public)s")
                throw GlyphPrintError.timedOut(operation)
            }

            guard let result = try await group.next() else {
                throw GlyphPrintError.internalInconsistency("Task group returned no result")
            }
            group.cancelAll()
            return result
        }
    }
}

extension GlyphPrinterClient: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.debug("centralManagerDidUpdateState: \(central.state.rawValue, privacy: .public)")
        scanStateUpdate()
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any],
                               rssi RSSI: NSNumber) {
        logger.debug("Discovered peripheral \(String(describing: peripheral.name), privacy: .public)")
        logger.debug("Stopping scan and attempting to connect to discovered peripheral")
        isScanning = false
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.debug("Connected to peripheral")
        logger.debug("Discovering services on peripheral: \(peripheral.identifier.uuidString, privacy: .public)")
        peripheral.discoverServices([CBUUID(string: config.serviceUUID)])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect to peripheral: \(peripheral.identifier.uuidString, privacy: .public) error: \(String(describing: error), privacy: .public)")
        failConnect(with: error ?? GlyphPrintError.connectionFailed("Unknown connect error"))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.debug("Disconnected from peripheral")
        if let error { logger.error("Disconnect error: \(error.localizedDescription, privacy: .public)") }
        notifyReady = false
        writeCharacteristic = nil
        notifyCharacteristic = nil
        if let error, let connectContinuation {
            self.connectContinuation = nil
            connectContinuation.resume(throwing: error)
        }
    }
}

extension GlyphPrinterClient: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        logger.debug("didDiscoverServices called. error: \(String(describing: error), privacy: .public)")
        if let error {
            failConnect(with: error)
            return
        }

        guard let services = peripheral.services else {
            logger.error("No services found on peripheral: \(peripheral.identifier.uuidString, privacy: .public)")
            failConnect(with: GlyphPrintError.missingService)
            return
        }

        for service in services where service.uuid == CBUUID(string: config.serviceUUID) {
            logger.debug("Discovering characteristics for service: \(service.uuid.uuidString, privacy: .public)")
            peripheral.discoverCharacteristics([
                CBUUID(string: config.writeCharacteristicUUID),
                CBUUID(string: config.notifyCharacteristicUUID)
            ], for: service)
            return
        }

        failConnect(with: GlyphPrintError.missingService)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        logger.debug("didDiscoverCharacteristicsFor service: \(service.uuid.uuidString, privacy: .public) error: \(String(describing: error), privacy: .public)")
        if let error {
            failConnect(with: error)
            return
        }

        guard let characteristics = service.characteristics else {
            failConnect(with: GlyphPrintError.missingWriteCharacteristic)
            return
        }

        for characteristic in characteristics {
            if characteristic.uuid == CBUUID(string: config.writeCharacteristicUUID) {
                writeCharacteristic = characteristic
                logger.debug("Found write characteristic: \(characteristic.uuid.uuidString, privacy: .public)")
            }
            if characteristic.uuid == CBUUID(string: config.notifyCharacteristicUUID) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                logger.debug("Found notify characteristic and enabling notifications: \(characteristic.uuid.uuidString, privacy: .public)")
            }
        }

        if notifyCharacteristic == nil {
            failConnect(with: GlyphPrintError.connectionFailed("Notify characteristic was not discovered."))
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        logger.debug("didUpdateNotificationStateFor: \(characteristic.uuid.uuidString, privacy: .public) isNotifying: \(characteristic.isNotifying, privacy: .public) error: \(String(describing: error), privacy: .public)")
        if let error {
            failConnect(with: error)
            return
        }

        guard characteristic.uuid == CBUUID(string: config.notifyCharacteristicUUID), characteristic.isNotifying else {
            return
        }

        notifyReady = true
        logger.debug("Notify characteristic is ready")
        logger.debug("Notify is ready; resuming connect continuation")
        if let continuation = connectContinuation {
            connectContinuation = nil
            continuation.resume()
        }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        logger.debug("peripheralIsReady(toSendWriteWithoutResponse)")
        guard let characteristic = writeCharacteristic else { return }
        flushQueue(peripheral: peripheral, characteristic: characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.error("Notify update failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let value = characteristic.value {
            logger.debug("Notify: \(value.hexString, privacy: .public)")
        }
    }
}
