import Foundation

/// Discovery hints are separate from the GATT service used after connecting.
public struct PrinterProfile: Sendable, Hashable, Codable {
    public let name: String
    public let advertisedServices: [String]
    public let namePrefixes: [String]
    public let serviceUUID: String
    public let writeUUID: String
    public let notifyUUID: String

    public init(name: String, advertisedServices: [String], namePrefixes: [String],
                serviceUUID: String = "AE30", writeUUID: String = "AE01", notifyUUID: String = "AE02") {
        self.name = name
        self.advertisedServices = advertisedServices
        self.namePrefixes = namePrefixes
        self.serviceUUID = serviceUUID
        self.writeUUID = writeUUID
        self.notifyUUID = notifyUUID
    }

    public static let px10 = PrinterProfile(name: "Luxorparts PX10", advertisedServices: ["AF30", "AE30"], namePrefixes: ["Luxorp.PX10"])
    public static let catPrinter = PrinterProfile(name: "5178 thermal printer", advertisedServices: ["AE30", "AF30"], namePrefixes: ["print", "GB01", "GT01", "GB02"])
    public static let supported: [PrinterProfile] = [.px10, .catPrinter]

    static func detect(name: String?, services: [String]) -> PrinterProfile? {
        if let byName = supported.first(where: { profile in
            profile.namePrefixes.contains { name?.localizedCaseInsensitiveContains($0) == true }
        }) { return byName }
        // An advertised AF30 service alone does not establish the exact printer model.
        return catPrinter.advertisedServices.contains { expected in
            services.contains { normalizedUUID($0) == normalizedUUID(expected) }
        } ? .catPrinter : nil
    }
}

func normalizedUUID(_ string: String) -> String {
    let value = string.uppercased()
    let suffix = "-0000-1000-8000-00805F9B34FB"
    if value.hasPrefix("0000"), value.hasSuffix(suffix), value.count == 36 {
        return String(value.dropFirst(4).prefix(4))
    }
    return value
}
