import Foundation

/// Holds ownership across suspension points, so packets from separate jobs cannot interleave.
actor PrintJobQueue {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var busy = false
    private var waiters: [Waiter] = []

    func send(_ packets: [Data], using transport: any GlyphPrinterTransport) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if busy {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            } else {
                busy = true
            }
            defer { release() }
            for packet in packets {
                try Task.checkCancellation()
                try await transport.send(packet)
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }
}
