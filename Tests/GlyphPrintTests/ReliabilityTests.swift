import Testing
import Foundation
import CoreGraphics
@testable import GlyphPrint

@Test(.timeLimit(.minutes(1))) func bleOperationTimesOutWithoutDelegateCallback() async throws {
    let operation = BLEOperation()
    do {
        try await operation.wait(timeout: .milliseconds(10), start: {}, cancel: {})
        Issue.record("Expected timeout")
    } catch GlyphPrintError.timedOut(let name) {
        #expect(name == "BLE connect")
    }
    #expect(operation.isFinished)
    #expect(!operation.finish(.success(())))
}

@Test(.timeLimit(.minutes(1))) func bleOperationCancellationUnblocksWaitingTask() async throws {
    let operation = BLEOperation()
    let started = BLEOperation()
    let task = Task {
        try await operation.wait(start: { started.finish(.success(())) }, cancel: {})
    }
    try await started.wait(start: {}, cancel: {})
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch is CancellationError {}
    #expect(operation.isFinished)
}

@Test func bleOperationHandlesCompletionBeforeRegistration() async throws {
    let operation = BLEOperation()
    operation.finish(.success(()))
    try await operation.wait(start: { Issue.record("Already completed operation started again") }, cancel: {})
    #expect(!operation.finish(.failure(GlyphPrintError.bluetoothUnavailable)))
}

@Test func bleOperationHandlesAlreadyCancelledTask() async throws {
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        try await BLEOperation().wait(start: { Issue.record("Cancelled operation started") }, cancel: {})
    }
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch is CancellationError {}
}

@Test func explicitNameMatchDoesNotSelectOtherPrinterByService() {
    let config = PrinterConfig(advertisedNameSubstring: "Kitchen", requiresNameMatch: true)
    #expect(!config.matchesDiscovery(identifier: UUID(), name: "Office", serviceUUIDs: ["AE30"]))
    #expect(config.matchesDiscovery(identifier: UUID(), name: "kitchen printer", serviceUUIDs: []))
    #expect(!config.matchesDiscovery(identifier: UUID(), name: nil, serviceUUIDs: ["AE30"]))
}

@Test func defaultDiscoveryStillAcceptsServiceAndUUIDSelectionIsStrict() {
    #expect(PrinterConfig.default.matchesDiscovery(identifier: UUID(), name: "Unusual name", serviceUUIDs: ["ae30"]))
    let target = UUID()
    let config = PrinterConfig(targetPeripheralIdentifier: target)
    #expect(config.matchesDiscovery(identifier: target, name: nil, serviceUUIDs: []))
    #expect(!config.matchesDiscovery(identifier: UUID(), name: "printer", serviceUUIDs: ["AE30"]))
}

@Test func transparentPixelsPrintAsWhite() throws {
    // Transparent black, half-transparent black, opaque black, then opaque white.
    let pixels: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 255] + Array(repeating: 255, count: 20)
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: 8, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let raster = try MonochromeRasterizer(targetWidth: 8).rasterize(image)
    #expect(raster.bytes == Data([0b01100000]))
}

@Test func invalidRasterDimensionsThrowInsteadOfTrapping() {
    for raster in [RasterImage(width: 0, height: 1, bytes: Data()),
                   RasterImage(width: 8, height: -1, bytes: Data()),
                   RasterImage(width: -8, height: -1, bytes: Data([0])),
                   RasterImage(width: Int.max - 7, height: 2, bytes: Data())] {
        #expect(throws: GlyphPrintError.self) { try GlyphProtocol.makeRasterPackets(from: raster) }
    }
}

@Test(.timeLimit(.minutes(1))) func concurrentPrintJobsDoNotInterleave() async throws {
    let queue = PrintJobQueue()
    let transport = YieldingTransport()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for job in UInt8(0)..<20 {
            group.addTask {
                try await queue.send(Array(repeating: Data([job]), count: 5), using: transport)
            }
        }
        try await group.waitForAll()
    }
    let sent = await transport.snapshot()
    #expect(sent.count == 100)
    for offset in stride(from: 0, to: sent.count, by: 5) {
        #expect(Set(sent[offset..<offset + 5]).count == 1)
    }
    #expect(Set(sent).count == 20)
}

@Test(.timeLimit(.minutes(1))) func failedPrintJobReleasesQueue() async throws {
    let queue = PrintJobQueue()
    let transport = YieldingTransport(failFirst: true)
    do {
        try await queue.send([Data([1]), Data([2])], using: transport)
        Issue.record("Expected send failure")
    } catch GlyphPrintError.sendFailed {}
    try await queue.send([Data([3])], using: transport)
    #expect(await transport.snapshot() == [Data([3])])
}

@Test(.timeLimit(.minutes(1))) func cancelledJobDoesNotSendRemainingPackets() async throws {
    let queue = PrintJobQueue()
    let started = BLEOperation()
    let transport = BlockingTransport(started: started)
    let task = Task { try await queue.send([Data([1]), Data([2])], using: transport) }
    try await started.wait(start: {}, cancel: {})
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch is CancellationError {}
    try await queue.send([Data([3])], using: transport)
    #expect(await transport.snapshot() == [Data([1]), Data([3])])
}

@Test(.timeLimit(.minutes(1))) func cancellingQueuedJobDoesNotCancelActiveJob() async throws {
    let queue = PrintJobQueue()
    let started = BLEOperation()
    let transport = BlockingTransport(started: started)
    let active = Task { try await queue.send([Data([1])], using: transport) }
    try await started.wait(start: {}, cancel: {})
    let waiting = Task { try await queue.send([Data([2])], using: transport) }
    // Keep the active send blocked while giving the second job time to enter the queue.
    try await Task.sleep(for: .milliseconds(20))
    waiting.cancel()
    do {
        _ = try await waiting.value
        Issue.record("Expected queued cancellation")
    } catch is CancellationError {}
    #expect(await transport.snapshot() == [Data([1])])
    active.cancel()
    do { _ = try await active.value } catch is CancellationError {}
    try await queue.send([Data([3])], using: transport)
    #expect(await transport.snapshot() == [Data([1]), Data([3])])
}

private actor YieldingTransport: GlyphPrinterTransport {
    private var packets: [Data] = []
    private var failFirst: Bool
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func connect(timeout: Duration) async throws {}
    func disconnect() async {}
    func send(_ data: Data) async throws {
        if failFirst {
            failFirst = false
            throw GlyphPrintError.sendFailed("Test failure")
        }
        packets.append(data)
        await Task.yield()
    }
    func snapshot() -> [Data] { packets }
}

private actor BlockingTransport: GlyphPrinterTransport {
    let started: BLEOperation
    private var packets: [Data] = []
    init(started: BLEOperation) { self.started = started }
    func connect(timeout: Duration) async throws {}
    func disconnect() async {}
    func send(_ data: Data) async throws {
        packets.append(data)
        if packets.count == 1 {
            started.finish(.success(()))
            try await Task.sleep(for: .seconds(60))
        }
    }
    func snapshot() -> [Data] { packets }
}
