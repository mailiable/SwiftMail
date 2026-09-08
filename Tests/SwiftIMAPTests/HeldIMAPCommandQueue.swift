@testable import SwiftMail

/// Holds a real connection queue until a test releases it, without occupying a thread.
final class HeldIMAPCommandQueue {
    private let started = AsyncStream<Void>.makeStream()
    private let releaseSignal = AsyncStream<Void>.makeStream()
    private let task: Task<Void, Never>

    init(_ queue: IMAPCommandQueue) {
        let started = self.started
        let releaseSignal = self.releaseSignal
        task = Task {
            await queue.run {
                started.continuation.finish()
                for await _ in releaseSignal.stream {}
            }
        }
    }

    func waitUntilHeld() async {
        for await _ in started.stream {}
    }

    func release() { releaseSignal.continuation.finish() }
    func finish() async { await task.value }
}
