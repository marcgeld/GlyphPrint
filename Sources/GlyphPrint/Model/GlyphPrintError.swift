import Foundation

public enum GlyphPrintError: Error, LocalizedError, Sendable {
    case bluetoothUnavailable
    case timedOut(String)
    case peripheralNotFound
    case missingService
    case missingWriteCharacteristic
    case invalidImage
    case unsupportedImageWidth(Int)
    case connectionFailed(String)
    case sendFailed(String)
    case internalInconsistency(String)

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable."
        case .timedOut(let operation):
            return "Timed out while waiting for \(operation)."
        case .peripheralNotFound:
            return "No compatible printer peripheral was found."
        case .missingService:
            return "Required BLE service was not discovered."
        case .missingWriteCharacteristic:
            return "Required BLE write characteristic was not discovered."
        case .invalidImage:
            return "The image could not be rasterized for printing."
        case .unsupportedImageWidth(let width):
            return "Unsupported image width: \(width)."
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .sendFailed(let message):
            return "Send failed: \(message)"
        case .internalInconsistency(let message):
            return "Internal inconsistency: \(message)"
        }
    }
}
