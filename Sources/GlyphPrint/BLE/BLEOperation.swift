import Foundation

/// A one-shot bridge that also handles cancellation before continuation registration.
/// The lock protects only bridge state; CoreBluetooth state stays on its serial queue.
final class BLEOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    var isFinished: Bool {
        lock.withLock { result != nil }
    }

    @discardableResult
    func finish(_ result: Result<Void, Error>, beforeResume: () -> Void = {}) -> Bool {
        let (won, continuation) = lock.withLock {
            guard self.result == nil else { return (false, Optional<CheckedContinuation<Void, Error>>.none) }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            return (true, continuation)
        }
        if won { beforeResume() }
        continuation?.resume(with: result)
        return won
    }

    func wait(
        timeout: Duration? = nil,
        start: @Sendable () -> Void,
        cancel: @escaping @Sendable () -> Void
    ) async throws {
        let timer = timeout.map { duration in
            Task {
                do {
                    try await Task.sleep(for: duration)
                    finish(.failure(GlyphPrintError.timedOut("BLE connect")), beforeResume: cancel)
                } catch { /* Timer cancelled after completion. */ }
            }
        }
        defer { timer?.cancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                let completed: Result<Void, Error>? = lock.withLock {
                    if let result { return result }
                    self.continuation = continuation
                    return nil
                }
                if let completed {
                    continuation.resume(with: completed)
                } else {
                    start()
                }
            }
        } onCancel: {
            self.finish(.failure(CancellationError()), beforeResume: cancel)
        }
    }
}
