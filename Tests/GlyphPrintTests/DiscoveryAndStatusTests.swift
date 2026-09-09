import Testing
import Foundation
@testable import GlyphPrint
@testable import GlyphPrintCLI

@Test func advertisedAF30IsOnlyACandidateUntilConnected() {
    let device = DiscoveredPrinter(id: UUID(), name: "Luxorp.PX10-1673", rssi: -62, advertisedServices: ["AF30"])
    #expect(device.profile == .px10)
    #expect(device.compatibility == .candidate)
    #expect(device.config.serviceUUID == "AE30")
    #expect(PrinterConfig.default.matchesDiscovery(identifier: device.id, name: device.name, serviceUUIDs: ["AF30"]))
    let unnamed = DiscoveredPrinter(id: UUID(), name: nil, rssi: -65, advertisedServices: ["0000af30-0000-1000-8000-00805f9b34fb"])
    #expect(unnamed.profile == .catPrinter)
}

@Test func ambiguousNamesNeverChooseFirstAdvertisement() throws {
    let first = DiscoveredPrinter(id: UUID(), name: "PX10 A", rssi: -30, advertisedServices: ["AF30"])
    let second = DiscoveredPrinter(id: UUID(), name: "PX10 B", rssi: -70, advertisedServices: ["AF30"])
    #expect(throws: GlyphPrintError.self) { try PrinterSelection.select(from: [first, second], matching: "PX10") }
    #expect(throws: GlyphPrintError.self) { try PrinterSelection.select(from: [first, second]) }
    #expect(try PrinterSelection.select(from: [second, first], matching: first.id.uuidString) == first)
    #expect(try PrinterSelection.select(from: [first, second], matching: "px10 b") == second)
}

@Test func explicitlySelectedPrinterBypassesRSSICutoff() {
    #expect(!PrinterConfig.default.acceptsRSSI(-100))
    #expect(PrinterConfig(targetPeripheralIdentifier: UUID()).acceptsRSSI(-100))
    #expect(PrinterConfig(advertisedNameSubstring: "PX10", requiresNameMatch: true).acceptsRSSI(-100))
    #expect(PrinterConfig.default.acceptsRSSI(127))
}

@Test func invalidScanDurationFailsWithoutBluetooth() async {
    await #expect(throws: GlyphPrintError.self) { try await PrinterDiscovery.discoverPrinters(duration: .zero) }
    await #expect(throws: GlyphPrintError.self) { try await PrinterDiscovery.discoverPrinters(duration: .seconds(61)) }
}

@Test func savedPrinterRoundTripsAndClears() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let preferences = PrinterPreferences(url: directory.appendingPathComponent("default.json"))
    #expect(try preferences.load() == nil)
    let saved = PrinterPreferences.SavedPrinter(id: UUID(), name: "PX10")
    try preferences.save(saved)
    #expect(try preferences.load() == saved)
    try preferences.clear()
    #expect(try preferences.load() == nil)
}

private func fixture(_ name: String) throws -> [String: String] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    let dictionary = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    return dictionary.compactMapValues { $0 as? String }
}

@Test func capturedPX10StatusDecodesAcrossEveryFragmentBoundary() throws {
    let sample = try fixture("px10-status")
    let raw = Data(hex: try #require(sample["notificationHex"]))
    for split in 0...raw.count {
        var decoder = PrinterNotificationDecoder()
        let messages = decoder.append(raw.prefix(split)) + decoder.append(raw.dropFirst(split))
        #expect(messages.count == 1)
        #expect(messages.first?.kind == .deviceState)
        #expect(messages.first?.payload == Data(hex: try #require(sample["payloadHex"])))
        #expect(messages.first?.raw == raw)
    }
}

@Test func referenceFlowControlAndMalformedNotifications() throws {
    let reference = try fixture("reference-packets")
    let ready = Data(hex: try #require(reference["readyHex"]))
    let pause = Data(hex: try #require(reference["pauseHex"]))
    var damaged = ready
    damaged[damaged.count - 2] ^= 1
    var decoder = PrinterNotificationDecoder()
    let result = decoder.append(Data([0, 1, 2]) + damaged + pause + ready)
    #expect(result.map(\.kind) == [.receivingPaused, .receivingReady])
}

@Test func CLIPrinterSelectionAndNumericValidation() throws {
    let options = try CLIOptions(["--printer", "PX10", "--image", "photo.jpg", "--dither", "--brightness", "0.2", "--contrast", "1.1"])
    #expect(options.printer == "PX10")
    #expect(options.action == .image("photo.jpg"))
    #expect(options.dither)
    for invalid in [["--seconds", "nan"], ["--seconds", "-1"], ["--seconds", "1e100"], ["--printer"],
                    ["--contrast", "inf"], ["--brightness", "2"], ["--wat"], ["--scan", "--status"]] {
        #expect(throws: GlyphPrintError.self) { try CLIOptions(invalid) }
    }
    #expect(try CLIOptions(["--", "--not-an-option"]).text == ["--not-an-option"])
    #expect(try CLIOptions(["Please", "scan", "me"]).text == ["Please", "scan", "me"])
}

@Test func brightnessContrastPreserveDefaultsAndClamp() {
    #expect(MonochromeRasterizer.adjust(80, brightness: 0, contrast: 1) == 80)
    #expect(MonochromeRasterizer.adjust(80, brightness: 0.2, contrast: 1) == 131)
    #expect(MonochromeRasterizer.adjust(240, brightness: 1, contrast: 4) == 255)
    #expect(MonochromeRasterizer.adjust(10, brightness: -1, contrast: 4) == 0)
    #expect(MonochromeRasterizer.adjust(10, brightness: 0, contrast: 0) == 127.5)
}

@Test func queueWaitsForJobCompletionBeforeNextJob() async throws {
    let queue = PrintJobQueue()
    let transport = CompletionTransport()
    async let first = queue.send([Data([1])], using: transport)
    async let second = queue.send([Data([2])], using: transport)
    _ = try await (first, second)
    #expect(await transport.events() == ["send", "finish", "send", "finish"])
}

private actor CompletionTransport: GlyphPrinterTransport {
    var recorded: [String] = []
    func connect(timeout: Duration) async throws {}
    func disconnect() async {}
    func send(_ data: Data) async throws { recorded.append("send"); await Task.yield() }
    func finishJob() async throws -> PrintResult {
        await Task.yield()
        recorded.append("finish")
        return .submittedToBluetooth
    }
    func events() -> [String] { recorded }
}

@Test func actualPrintNotificationsRemainLosslessIncludingUnknownCommands() throws {
    let url = try #require(Bundle.module.url(forResource: "px10-print-notifications", withExtension: "json", subdirectory: "Fixtures"))
    let captured = try JSONDecoder().decode([PrinterNotification].self, from: Data(contentsOf: url))
    #expect(captured.contains { $0.command == 0xA8 && $0.kind == .unknown })
    #expect(captured.contains { $0.command == 0xA3 && $0.kind == .deviceState })
    var decoder = PrinterNotificationDecoder()
    let wire = captured.reduce(into: Data()) { $0.append($1.raw) }
    var result: [PrinterNotification] = []
    for byte in wire { result += decoder.append(Data([byte])) }
    #expect(result == captured)
}
