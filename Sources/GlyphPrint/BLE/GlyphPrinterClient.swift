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
    func disconnect() async
    func send(_ data: Data) async throws
}

public actor GlyphPrinterClient: GlyphPrinterTransport {
    private let coordinator: GlyphPrinterBLECoordinator

    public init(config: PrinterConfig = .default, queue: DispatchQueue? = nil) {
        self.coordinator = GlyphPrinterBLECoordinator(config: config, queue: queue)
    }

    public func connect(timeout: Duration = .seconds(30)) async throws {
        try await coordinator.connect(timeout: timeout)
    }

    public func disconnect() async {
        await coordinator.disconnect()
    }

    public func send(_ data: Data) async throws {
        try await coordinator.send(data)
    }
}

private final class GlyphPrinterBLECoordinator: NSObject, @unchecked Sendable {
    private let config: PrinterConfig
    private let queue: DispatchQueue
    private let logger = Logger.glyphPrintBLE

    private var central: CBCentralManager!

    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var connectContinuation: BLEOperation?
    private var sendContinuation: BLEOperation?

    private var pendingChunks: [Data] = []
    private var notifyReady = false
    private var isScanning = false
    private var userInitiatedDisconnect = false

    init(config: PrinterConfig, queue: DispatchQueue?) {
        self.config = config
        self.queue = DispatchQueue(label: "GlyphPrint.BLE", target: queue)
        super.init()
        self.central = CBCentralManager(delegate: self, queue: self.queue)
    }

    func connect(timeout: Duration = .seconds(30)) async throws {
        let operation = BLEOperation()
        try await operation.wait(timeout: timeout) {
            self.queue.async {
                guard !operation.isFinished else { return }
                if self.peripheral?.state == .connected, self.notifyReady, self.writeCharacteristic != nil {
                    operation.finish(.success(()))
                    return
                }
                guard self.connectContinuation == nil else {
                    operation.finish(.failure(GlyphPrintError.connectionFailed("A connect operation is already in progress.")))
                    return
                }
                self.userInitiatedDisconnect = false
                self.connectContinuation = operation
                self.startScanIfPossible()
            }
        } cancel: {
            self.queue.async {
                guard self.connectContinuation === operation else { return }
                self.cancelOutstandingConnect()
            }
        }
    }

    func disconnect() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.logger.debug("disconnect() called")
                self.userInitiatedDisconnect = true
                self.stopScan()

                if let peripheral = self.peripheral {
                    self.central.cancelPeripheralConnection(peripheral)
                }

                self.clearConnectionState()
                self.resumeSendIfNeeded(with: .failure(GlyphPrintError.connectionFailed("Disconnected.")))
                self.resumeConnectIfNeeded(with: .failure(GlyphPrintError.connectionFailed("Disconnected.")))
                continuation.resume()
            }
        }
    }

    func send(_ data: Data) async throws {
        let operation = BLEOperation()
        try await operation.wait {
            self.queue.async {
                guard !operation.isFinished else { return }
                guard self.notifyReady else {
                    operation.finish(.failure(GlyphPrintError.connectionFailed("Notify channel is not ready.")))
                    return
                }

                guard let peripheral = self.peripheral, peripheral.state == .connected else {
                    operation.finish(.failure(GlyphPrintError.connectionFailed("Peripheral is not connected.")))
                    return
                }

                guard let characteristic = self.writeCharacteristic else {
                    operation.finish(.failure(GlyphPrintError.missingWriteCharacteristic))
                    return
                }

                let maxLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
                self.logger.debug(
                    "Queueing \(data.count, privacy: .public) bytes using max chunk \(maxLength, privacy: .public)"
                )

                guard maxLength > 0 else {
                    operation.finish(.failure(GlyphPrintError.sendFailed("maximumWriteValueLength returned 0")))
                    return
                }

                if self.sendContinuation != nil {
                    operation.finish(.failure(GlyphPrintError.sendFailed("Another send operation is already in progress.")))
                    return
                }

                self.sendContinuation = operation
                self.pendingChunks = Self.chunk(data: data, chunkSize: maxLength)
                self.flushQueue(peripheral: peripheral, characteristic: characteristic)
            }
        } cancel: {
            self.queue.async {
                guard self.sendContinuation === operation else { return }
                self.pendingChunks.removeAll()
                self.sendContinuation = nil
                // A partial packet cannot safely be followed by another job.
                if let peripheral = self.peripheral {
                    self.central.cancelPeripheralConnection(peripheral)
                }
                self.clearConnectionState()
            }
        }
    }

    private func startScanIfPossible() {
        guard connectContinuation != nil else { return }
        logger.debug("startScanIfPossible() invoked. Central state: \(self.central.state.logDescription, privacy: .public)")

        switch central.state {
        case .poweredOn:
            if notifyReady,
               let peripheral,
               peripheral.state == .connected,
               writeCharacteristic != nil {
                logger.debug("Peripheral already connected and notify-ready; completing connect immediately")
                resumeConnectIfNeeded(with: .success(()))
                return
            }

            guard !isScanning else {
                logger.debug("Scan already in progress")
                return
            }

            guard peripheral == nil else {
                logger.debug("A candidate peripheral is already being evaluated")
                return
            }

            isScanning = true
            logger.debug("Starting BLE scan without service filter")
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

        case .unsupported:
            logger.error("Bluetooth unsupported on this device")
            failConnect(with: GlyphPrintError.bluetoothUnavailable)

        case .unauthorized:
            logger.error("Bluetooth unauthorized")
            failConnect(with: GlyphPrintError.bluetoothUnavailable)

        case .poweredOff:
            logger.error("Bluetooth powered off")
            failConnect(with: GlyphPrintError.bluetoothUnavailable)

        case .resetting:
            logger.debug("Bluetooth resetting; waiting for another state update")

        case .unknown:
            logger.debug("Bluetooth state unknown; waiting for another state update")

        @unknown default:
            logger.error("Bluetooth state unrecognized")
            failConnect(with: GlyphPrintError.bluetoothUnavailable)
        }
    }

    private func stopScan() {
        guard isScanning else { return }
        logger.debug("Stopping BLE scan")
        isScanning = false
        central.stopScan()
    }

    private func clearConnectionState() {
        pendingChunks.removeAll()
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        notifyReady = false
    }

    private func cancelOutstandingConnect() {
        stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        clearConnectionState()
        connectContinuation = nil
    }

    private func failConnect(with error: Error) {
        stopScan()
        clearConnectionState()
        resumeConnectIfNeeded(with: .failure(error))
    }

    private func rejectCurrentCandidateAndResumeScanning(reason: String) {
        logger.debug("Rejecting candidate peripheral: \(reason, privacy: .public)")

        notifyReady = false
        writeCharacteristic = nil
        notifyCharacteristic = nil

        if let peripheral = self.peripheral {
            self.central.cancelPeripheralConnection(peripheral)
        } else {
            startScanIfPossible()
        }
    }

    private func resumeConnectIfNeeded(with result: Result<Void, Error>) {
        guard let continuation = connectContinuation else { return }
        if continuation.finish(result) { connectContinuation = nil }
    }

    private func resumeSendIfNeeded(with result: Result<Void, Error>) {
        guard let continuation = sendContinuation else { return }
        if continuation.finish(result) { sendContinuation = nil }
    }

    private func flushQueue(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        logger.debug("Flushing write queue. Pending chunks: \(self.pendingChunks.count, privacy: .public)")

        while peripheral.canSendWriteWithoutResponse, !pendingChunks.isEmpty,
              sendContinuation?.isFinished == false {
            let chunk = pendingChunks.removeFirst()
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            logger.debug("Sent chunk \(chunk.count, privacy: .public) bytes")
        }

        if pendingChunks.isEmpty {
            resumeSendIfNeeded(with: .success(()))
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


}

extension GlyphPrinterBLECoordinator: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.debug("centralManagerDidUpdateState: \(central.state.logDescription, privacy: .public)")
        if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported || central.state == .resetting {
            stopScan()
            clearConnectionState()
            resumeSendIfNeeded(with: .failure(GlyphPrintError.bluetoothUnavailable))
            resumeConnectIfNeeded(with: .failure(GlyphPrintError.bluetoothUnavailable))
            return
        }
        startScanIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? "unknown"
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []

        logger.debug(
            """
            Discovered peripheral:
            name: \(name, privacy: .public)
            id: \(peripheral.identifier.uuidString, privacy: .public)
            rssi: \(RSSI.intValue, privacy: .public)
            advertisedServices: \(serviceUUIDs.map(\.uuidString).joined(separator: ","), privacy: .public)
            """
        )

        guard connectContinuation != nil else {
            logger.debug("Ignoring discovery because no connect operation is active")
            return
        }

        guard self.peripheral == nil else {
            logger.debug("Already evaluating a peripheral; ignoring discovery")
            return
        }

        guard RSSI.intValue >= config.minimumRSSI else {
            logger.debug("Device has too low RSSI: \(RSSI.intValue, privacy: .public); discarding")
            return
        }

        guard isDiscoveryCandidate(
            identifier: peripheral.identifier,
            name: peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String),
            serviceUUIDs: serviceUUIDs
        ) else {
            logger.debug("Peripheral did not match discovery filters; ignoring")
            return
        }

        logger.debug("Selected candidate \(name, privacy: .public)")
        stopScan()

        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    private func isDiscoveryCandidate(identifier: UUID, name: String?, serviceUUIDs: [CBUUID]) -> Bool {
        config.matchesDiscovery(identifier: identifier, name: name, serviceUUIDs: serviceUUIDs.map(\.uuidString))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        logger.debug("Connected to peripheral \(peripheral.identifier.uuidString, privacy: .public)")
        logger.debug("Discovering services on peripheral")
        peripheral.discoverServices([CBUUID(string: config.serviceUUID)])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.error(
            "Failed to connect to peripheral: \(peripheral.identifier.uuidString, privacy: .public) error: \(String(describing: error), privacy: .public)"
        )

        guard self.peripheral === peripheral else { return }
        clearConnectionState()

        if connectContinuation != nil {
            startScanIfPossible()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.debug("Disconnected from peripheral \(peripheral.identifier.uuidString, privacy: .public)")

        if let error {
            logger.error("Disconnect error: \(error.localizedDescription, privacy: .public)")
        }

        guard self.peripheral === peripheral else { return }
        clearConnectionState()

        if userInitiatedDisconnect {
            logger.debug("Disconnect was user initiated")
            userInitiatedDisconnect = false
            return
        }

        if let error, connectContinuation != nil {
            logger.debug("Disconnect happened during connect flow; resuming scan")
            logger.debug("""
            Error:
            type: \(String(describing: type(of: error)), privacy: .public)
            message: \(error.localizedDescription, privacy: .public)
            """)
            startScanIfPossible()
            return
        }

        if connectContinuation != nil {
            logger.debug("Disconnected before connect completed; resuming scan")
            startScanIfPossible()
            return
        }

        if sendContinuation != nil {
            resumeSendIfNeeded(with: .failure(error ?? GlyphPrintError.connectionFailed("Disconnected during send.")))
        }
    }
}

extension GlyphPrinterBLECoordinator: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        logger.debug("didDiscoverServices called. error: \(String(describing: error), privacy: .public)")

        if let error {
            rejectCurrentCandidateAndResumeScanning(reason: "service discovery failed: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            rejectCurrentCandidateAndResumeScanning(reason: "no services found")
            return
        }

        let targetServiceUUID = CBUUID(string: config.serviceUUID)

        guard let service = services.first(where: { $0.uuid == targetServiceUUID }) else {
            rejectCurrentCandidateAndResumeScanning(reason: "target service \(config.serviceUUID) not found")
            return
        }

        logger.debug("Discovering characteristics for service \(service.uuid.uuidString, privacy: .public)")
        peripheral.discoverCharacteristics(
            [
                CBUUID(string: config.writeCharacteristicUUID),
                CBUUID(string: config.notifyCharacteristicUUID)
            ],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        logger.debug(
            "didDiscoverCharacteristicsFor service: \(service.uuid.uuidString, privacy: .public) error: \(String(describing: error), privacy: .public)"
        )

        if let error {
            rejectCurrentCandidateAndResumeScanning(reason: "characteristic discovery failed: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics, !characteristics.isEmpty else {
            rejectCurrentCandidateAndResumeScanning(reason: "no characteristics found")
            return
        }

        let writeUUID = CBUUID(string: config.writeCharacteristicUUID)
        let notifyUUID = CBUUID(string: config.notifyCharacteristicUUID)

        writeCharacteristic = nil
        notifyCharacteristic = nil

        for characteristic in characteristics {
            if characteristic.uuid == writeUUID {
                writeCharacteristic = characteristic
                logger.debug("Found write characteristic: \(characteristic.uuid.uuidString, privacy: .public)")
            }

            if characteristic.uuid == notifyUUID {
                notifyCharacteristic = characteristic
                logger.debug("Found notify characteristic: \(characteristic.uuid.uuidString, privacy: .public)")
            }
        }

        guard let notifyCharacteristic else {
            rejectCurrentCandidateAndResumeScanning(reason: "notify characteristic not found")
            return
        }

        guard writeCharacteristic != nil else {
            rejectCurrentCandidateAndResumeScanning(reason: "write characteristic not found")
            return
        }

        logger.debug("Enabling notifications")
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        logger.debug(
            "didUpdateNotificationStateFor: \(characteristic.uuid.uuidString, privacy: .public) isNotifying: \(characteristic.isNotifying, privacy: .public) error: \(String(describing: error), privacy: .public)"
        )

        if let error {
            rejectCurrentCandidateAndResumeScanning(reason: "notify enable failed: \(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == CBUUID(string: config.notifyCharacteristicUUID) else {
            return
        }

        guard characteristic.isNotifying else {
            rejectCurrentCandidateAndResumeScanning(reason: "notify characteristic is not notifying")
            return
        }

        notifyReady = true
        logger.debug("Notify characteristic is ready; connect flow completed")
        resumeConnectIfNeeded(with: .success(()))
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        logger.debug("peripheralIsReady(toSendWriteWithoutResponse)")

        guard let characteristic = writeCharacteristic else { return }
        flushQueue(peripheral: peripheral, characteristic: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            logger.error("Notify update failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        if let value = characteristic.value {
            logger.debug("Notify: \(value.hexString, privacy: .public)")
        }
    }
}
