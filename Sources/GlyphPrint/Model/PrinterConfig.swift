import Foundation

public struct PrinterConfig: Sendable, Hashable {
    public let candidateTimeout: Duration
    public let sendTimeout: Duration
    public let writeInterval: Duration
    public let imageWidth: Int
    public let serviceUUID: String
    public let writeCharacteristicUUID: String
    public let notifyCharacteristicUUID: String
    public let minimumRSSI: Int
    public let advertisedNameSubstring: String?
    public let targetPeripheralIdentifier: UUID?
    /// Require the configured name filter, even when the BLE service matches.
    public let requiresNameMatch: Bool

    public init(
        imageWidth: Int = 384,
        serviceUUID: String = "AE30",
        writeCharacteristicUUID: String = "AE01",
        notifyCharacteristicUUID: String = "AE02",
        minimumRSSI: Int = -80,
        advertisedNameSubstring: String? = "print",
        targetPeripheralIdentifier: UUID? = nil,
        requiresNameMatch: Bool = false,
        candidateTimeout: Duration = .seconds(8),
        sendTimeout: Duration = .seconds(15),
        writeInterval: Duration = .milliseconds(10)
    ) {
        self.candidateTimeout = candidateTimeout
        self.sendTimeout = sendTimeout
        self.writeInterval = writeInterval
        self.imageWidth = imageWidth
        self.serviceUUID = serviceUUID
        self.writeCharacteristicUUID = writeCharacteristicUUID
        self.notifyCharacteristicUUID = notifyCharacteristicUUID
        self.minimumRSSI = minimumRSSI
        self.advertisedNameSubstring = advertisedNameSubstring
        self.targetPeripheralIdentifier = targetPeripheralIdentifier
        self.requiresNameMatch = requiresNameMatch
    }

    func acceptsRSSI(_ rssi: Int) -> Bool {
        targetPeripheralIdentifier != nil || requiresNameMatch || rssi == 127 || rssi >= minimumRSSI
    }

    func targeting(_ id: UUID) -> PrinterConfig {
        PrinterConfig(imageWidth: imageWidth, serviceUUID: serviceUUID,
            writeCharacteristicUUID: writeCharacteristicUUID, notifyCharacteristicUUID: notifyCharacteristicUUID,
            minimumRSSI: minimumRSSI, advertisedNameSubstring: nil, targetPeripheralIdentifier: id,
            candidateTimeout: candidateTimeout, sendTimeout: sendTimeout, writeInterval: writeInterval)
    }

    func matchesDiscovery(identifier: UUID, name: String?, serviceUUIDs: [String]) -> Bool {
        if let targetPeripheralIdentifier { return identifier == targetPeripheralIdentifier }
        let nameMatches = advertisedNameSubstring.map {
            !$0.isEmpty && name?.localizedCaseInsensitiveContains($0) == true
        } ?? false
        if requiresNameMatch { return nameMatches }
        return nameMatches || serviceUUIDs.contains { normalizedUUID($0) == normalizedUUID(serviceUUID) }
            || (normalizedUUID(serviceUUID) == "AE30" && PrinterProfile.detect(name: name, services: serviceUUIDs) != nil)
    }

    public static let `default` = PrinterConfig()
}
