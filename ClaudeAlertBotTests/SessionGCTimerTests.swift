import XCTest
@testable import ClaudeAlertBot

@MainActor
final class SessionGCTimerTests: XCTestCase {
    func test_timer_constructionAndStart_doesNotCrash() async {
        let t = SessionGCTimer(interval: 1.0, onTick: {})
        t.start()
        t.cancel()
    }

    func test_timer_handlerFires_atShortInterval() async throws {
        var count = 0
        let lock = NSLock()
        let timer = SessionGCTimer(interval: 0.1) {
            lock.lock(); defer { lock.unlock() }
            count += 1
        }
        timer.start()
        try await Task.sleep(nanoseconds: 350_000_000)   // 0.35s
        timer.cancel()
        let observedCount = lock.withLock { count }
        XCTAssertGreaterThanOrEqual(observedCount, 2, "Got count=\(observedCount)")
    }

    func test_timer_cancelStopsHandler() async throws {
        var count = 0
        let lock = NSLock()
        let timer = SessionGCTimer(interval: 0.1) {
            lock.lock(); defer { lock.unlock() }
            count += 1
        }
        timer.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        timer.cancel()
        let frozenCount: Int = { lock.lock(); defer { lock.unlock() }; return count }()
        try await Task.sleep(nanoseconds: 500_000_000)
        let after: Int = { lock.lock(); defer { lock.unlock() }; return count }()
        XCTAssertEqual(after, frozenCount, "handler fired after cancel: pre=\(frozenCount) post=\(after)")
    }

    func test_timer_isRetained_handlerFiresPostInit() async throws {
        var fired = false
        let lock = NSLock()
        var timer: SessionGCTimer? = SessionGCTimer(interval: 0.1) {
            lock.lock(); defer { lock.unlock() }
            fired = true
        }
        timer?.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        let result: Bool = { lock.lock(); defer { lock.unlock() }; return fired }()
        XCTAssertTrue(result)
        timer?.cancel()
        timer = nil
    }
}
