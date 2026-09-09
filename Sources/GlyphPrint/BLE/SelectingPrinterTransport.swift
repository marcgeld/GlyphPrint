import Foundation

/// Resolves automatic/name selection once before using the low-level transport.
/// This keeps the facade from choosing whichever advertisement happens to arrive first.
actor SelectingPrinterTransport: GlyphPrinterTransport {
    private let config: PrinterConfig
    private var client: GlyphPrinterClient?
    private var pending: Task<GlyphPrinterClient, Error>?
    private var generation = UUID()

    init(config: PrinterConfig) { self.config = config }

    func connect(timeout: Duration) async throws {
        guard pending == nil else { throw GlyphPrintError.connectionFailed("Connection already in progress.") }
        guard timeout > .zero else { throw GlyphPrintError.invalidArgument("Connection timeout must be positive.") }
        if let client { try await client.connect(timeout: timeout); return }
        let token = UUID()
        generation = token
        let config = self.config
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        let task = Task {
            let resolved: PrinterConfig
            if config.targetPeripheralIdentifier != nil { resolved = config }
            else {
                let devices = try await PrinterDiscovery.discoverPrinters(duration: min(.seconds(5), timeout), printersOnly: false)
                    .filter { config.matchesDiscovery(identifier: $0.id, name: $0.name, serviceUUIDs: $0.advertisedServices) && config.acceptsRSSI($0.rssi) }
                guard !devices.isEmpty else { throw GlyphPrintError.peripheralNotFound }
                guard devices.count == 1 else { throw GlyphPrintError.ambiguousPrinters(devices.map(\.id)) }
                resolved = config.targeting(devices[0].id)
            }
            try Task.checkCancellation()
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { throw GlyphPrintError.timedOut("printer selection") }
            let client = GlyphPrinterClient(config: resolved)
            do {
                try await client.connect(timeout: remaining)
                try Task.checkCancellation()
                return client
            } catch {
                await client.disconnect()
                throw error
            }
        }
        pending = task
        let timer = Task {
            do { try await Task.sleep(for: timeout); task.cancel() }
            catch { /* Connection completed before the deadline. */ }
        }
        defer { timer.cancel() }
        defer { if generation == token { pending = nil } }
        let connected: GlyphPrinterClient
        do {
            connected = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch {
            if !Task.isCancelled, clock.now >= deadline { throw GlyphPrintError.timedOut("BLE connect") }
            throw error
        }
        guard generation == token, !Task.isCancelled else {
            await connected.disconnect()
            throw CancellationError()
        }
        client = connected
    }

    func disconnect() async {
        generation = UUID()
        pending?.cancel()
        pending = nil
        let previous = client
        client = nil
        await previous?.disconnect()
    }
    func send(_ data: Data) async throws {
        guard let client else { throw GlyphPrintError.connectionFailed("Not connected.") }
        try await client.send(data)
    }
    func finishJob() async throws -> PrintResult {
        guard let client else { throw GlyphPrintError.connectionFailed("Not connected.") }
        return try await client.finishJob()
    }
}
