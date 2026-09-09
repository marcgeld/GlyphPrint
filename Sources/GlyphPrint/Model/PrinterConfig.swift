import Foundation

public struct PrinterConfig: Sendable, Hashable {
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
        requiresNameMatch: Bool = false
    ) {
        self.imageWidth = imageWidth
        self.serviceUUID = serviceUUID
        self.writeCharacteristicUUID = writeCharacteristicUUID
        self.notifyCharacteristicUUID = notifyCharacteristicUUID
        self.minimumRSSI = minimumRSSI
        self.advertisedNameSubstring = advertisedNameSubstring
        self.targetPeripheralIdentifier = targetPeripheralIdentifier
        self.requiresNameMatch = requiresNameMatch
    }

    func matchesDiscovery(identifier: UUID, name: String?, serviceUUIDs: [String]) -> Bool {
        if let targetPeripheralIdentifier { return identifier == targetPeripheralIdentifier }
        let nameMatches = advertisedNameSubstring.map {
            !$0.isEmpty && name?.localizedCaseInsensitiveContains($0) == true
        } ?? false
        if requiresNameMatch { return nameMatches }
        return nameMatches || serviceUUIDs.contains { $0.caseInsensitiveCompare(serviceUUID) == .orderedSame }
    }

    public static let `default` = PrinterConfig()
}
