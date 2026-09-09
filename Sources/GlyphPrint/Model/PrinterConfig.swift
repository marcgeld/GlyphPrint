import Foundation

public struct PrinterConfig: Sendable, Hashable {
    public let imageWidth: Int
    public let serviceUUID: String
    public let writeCharacteristicUUID: String
    public let notifyCharacteristicUUID: String

    public init(
        imageWidth: Int = 384,
        serviceUUID: String = "AE30",
        writeCharacteristicUUID: String = "AE01",
        notifyCharacteristicUUID: String = "AE02"
    ) {
        self.imageWidth = imageWidth
        self.serviceUUID = serviceUUID
        self.writeCharacteristicUUID = writeCharacteristicUUID
        self.notifyCharacteristicUUID = notifyCharacteristicUUID
    }

    public static let `default` = PrinterConfig()
}
