import Foundation

public struct PrinterNotification: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case deviceState, receivingPaused, receivingReady, unknown }
    public let command: UInt8
    public let payload: Data
    public let raw: Data
    public let kind: Kind

    init(command: UInt8, payload: Data, raw: Data) {
        self.command = command
        self.payload = payload
        self.raw = raw
        switch (command, Array(payload)) {
        case (0xA3, _): kind = .deviceState
        case (0xAE, [0x10]): kind = .receivingPaused
        case (0xAE, [0x00]): kind = .receivingReady
        default: kind = .unknown
        }
    }
}

/// Incrementally decodes fragmented/concatenated response frames and rejects bad CRCs.
/// A3 bytes remain raw until their meaning has been verified on the specific model.
public struct PrinterNotificationDecoder: Sendable {
    private var buffer: [UInt8] = []
    public init() {}

    public mutating func append(_ data: Data) -> [PrinterNotification] {
        buffer.append(contentsOf: data)
        var decoded: [PrinterNotification] = []
        while buffer.count >= 6 {
            guard buffer[0] == 0x51, buffer[1] == 0x78, buffer[3] == 1 else {
                buffer.removeFirst()
                continue
            }
            let length = Int(buffer[4]) | Int(buffer[5]) << 8
            guard length <= 4096 else { buffer.removeFirst(); continue }
            let count = length + 8
            guard buffer.count >= count else { break }
            let payload = Data(buffer[6..<6 + length])
            guard buffer[count - 1] == 0xFF, CRC8.checksum(payload) == buffer[count - 2] else {
                buffer.removeFirst()
                continue
            }
            decoded.append(PrinterNotification(command: buffer[2], payload: payload, raw: Data(buffer.prefix(count))))
            buffer.removeFirst(count)
        }
        return decoded
    }
}

public enum PrintResult: String, Sendable {
    /// CoreBluetooth accepted all bytes; physical completion is not known.
    case submittedToBluetooth
    /// A fresh receive-ready notification followed the final write. This is not proof of print quality.
    case printerReportedReady
}
