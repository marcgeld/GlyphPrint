import Foundation

public struct DiscoveredPrinter: Sendable, Hashable, Codable, Identifiable {
    public enum Compatibility: String, Sendable, Codable { case unknown, candidate, verified, unverified }
    public let id: UUID
    public let name: String?
    public let rssi: Int
    public let advertisedServices: [String]
    public let profile: PrinterProfile?
    public internal(set) var compatibility: Compatibility
    public internal(set) var verificationError: String?
    public var hasWeakSignal: Bool { rssi != 127 && rssi < -80 }

    public init(id: UUID, name: String?, rssi: Int, advertisedServices: [String]) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.advertisedServices = advertisedServices
        self.profile = PrinterProfile.detect(name: name, services: advertisedServices)
        self.compatibility = profile == nil ? .unknown : .candidate
    }

    public var config: PrinterConfig {
        let profile = profile ?? .catPrinter
        return PrinterConfig(serviceUUID: profile.serviceUUID, writeCharacteristicUUID: profile.writeUUID,
            notifyCharacteristicUUID: profile.notifyUUID, advertisedNameSubstring: nil, targetPeripheralIdentifier: id)
    }
}

public enum PrinterSelection {
    /// A name is a case-insensitive substring. Ambiguous selections never choose arbitrarily.
    public static func select(from devices: [DiscoveredPrinter], matching target: String? = nil) throws -> DiscoveredPrinter {
        let matches: [DiscoveredPrinter]
        if let target, let id = UUID(uuidString: target) {
            matches = devices.filter { $0.id == id }
        } else if let target, !target.isEmpty {
            matches = devices.filter { $0.name?.localizedCaseInsensitiveContains(target) == true }
        } else {
            matches = devices.filter { $0.profile != nil }
        }
        guard !matches.isEmpty else { throw GlyphPrintError.peripheralNotFound }
        guard matches.count == 1 else { throw GlyphPrintError.ambiguousPrinters(matches.map(\.id)) }
        return matches[0]
    }

    /// UUIDs connect directly; names and automatic selection first discover candidates.
    public static func configuration(for target: String? = nil, duration: Duration = .seconds(5)) async throws -> PrinterConfig {
        if let target, let id = UUID(uuidString: target) {
            return PrinterConfig(advertisedNameSubstring: nil, targetPeripheralIdentifier: id)
        }
        let devices = try await PrinterDiscovery.discoverPrinters(duration: duration, printersOnly: target == nil)
        return try select(from: devices, matching: target).config
    }
}
