import Foundation

extension Data {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
        self.init()
        guard cleaned.count >= 2 else { return }
        self.reserveCapacity(cleaned.count / 2)

        // Only process pairs of hex characters; ignore a trailing odd character.
        let pairCount = cleaned.count / 2
        var index = cleaned.startIndex
        for _ in 0..<pairCount {
            let next = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<next]
            if let byte = UInt8(byteString, radix: 16) {
                self.append(byte)
            }
            index = next
        }
    }

    var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}
