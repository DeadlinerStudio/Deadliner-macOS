import XCTest
import Shared
import UserNotifications
@testable import DeadlinerTestHost

/// 内存中的系统通知中心：记录添加、删除和查询的次数。
final class FakeNotificationCenter: PendingNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String: UNNotificationRequest] = [:]
    private(set) var adds = 0
    private(set) var removes: [String] = []
    private(set) var queries = 0

    var identifiers: Set<String> { lock.withLock { Set(requests.keys) } }
    func request(_ id: String) -> UNNotificationRequest? { lock.withLock { requests[id] } }

    func pendingRequests(_ completion: @escaping @Sendable ([UNNotificationRequest]) -> Void) {
        nonisolated(unsafe) let snapshot = lock.withLock { queries += 1; return Array(requests.values) }
        DispatchQueue.global().async { completion(snapshot) }
    }

    func remove(_ identifiers: [String]) {
        lock.withLock {
            removes += identifiers
            identifiers.forEach { requests[$0] = nil }
        }
    }

    func add(_ request: UNNotificationRequest) {
        lock.withLock {
            adds += 1
            requests[request.identifier] = request
        }
    }
}

/// 一周日志里发现的问题：通知反复重排、同步临时错误、诊断日志。
final class NotificationSinkTests: XCTestCase {
    private func plan(_ id: String, title: String = "提醒", hours: Double = 2) -> PlannedNotification {
        PlannedNotification(id: "deadliner.\(id)", ownerUid: id, kind: "TASK_DUE", title: title, body: "到期",
                            fireAt: Date().addingTimeInterval(hours * 3600))
    }

    private func settle(_ sink: UserNotificationSink) {
        let done = expectation(description: "idle")
        sink.whenIdle { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testSamePlanIsNotAddedAgainAndOnlyChangesAreApplied() {
        let center = FakeNotificationCenter()
        let sink = UserNotificationSink(center: center, coalesceDelay: 0)
        sink.replaceAll(with: [plan("a"), plan("b")])
        settle(sink)
        XCTAssertEqual(center.adds, 2)

        // 内容和时间都没变：不重新添加，也不删除。
        let a = plan("a"), b = plan("b")
        sink.replaceAll(with: [a, b])
        settle(sink)
        sink.replaceAll(with: [a, b])
        settle(sink)
        XCTAssertLessThanOrEqual(center.adds, 4, "时间按秒比较，最多因为跨秒重加一次")
        let before = center.adds
        sink.replaceAll(with: [a, b])
        settle(sink)
        XCTAssertEqual(center.adds, before)
        XCTAssertTrue(center.removes.isEmpty)

        // 只改了一条：只添加这一条；去掉的一条被删除。
        sink.replaceAll(with: [PlannedNotification(id: a.id, ownerUid: a.ownerUid, kind: a.kind, title: "改了标题", body: a.body, fireAt: a.fireAt)])
        settle(sink)
        XCTAssertEqual(center.adds, before + 1)
        XCTAssertEqual(center.removes, ["deadliner.b"])
        XCTAssertEqual(center.request("deadliner.a")?.content.title, "改了标题")
    }

    func testBurstOfPlansIsCoalescedAndTheLatestWins() {
        let center = FakeNotificationCenter()
        let sink = UserNotificationSink(center: center, coalesceDelay: 0.2)
        for index in 0..<10 { sink.replaceAll(with: [plan("x\(index)")]) }
        settle(sink)
        XCTAssertEqual(center.queries, 1, "短时间内的多次重排只执行一次")
        XCTAssertEqual(center.identifiers, ["deadliner.x9"])
    }

    func testOtherRequestsAndPastItemsAreLeftAlone() {
        let center = FakeNotificationCenter()
        center.add(UNNotificationRequest(identifier: DailySummary.identifier, content: UNMutableNotificationContent(), trigger: nil))
        let sink = UserNotificationSink(center: center, coalesceDelay: 0)
        sink.replaceAll(with: [plan("old", hours: -1), plan("new")])
        settle(sink)
        XCTAssertEqual(center.identifiers, [DailySummary.identifier, "deadliner.new"])
        sink.removeAll()
        settle(sink)
        XCTAssertEqual(center.identifiers, [DailySummary.identifier])
    }

    func testDailySummaryOnlyTouchesTheCenterWhenSomethingChanges() {
        let defaults = UserDefaults(suiteName: "deadliner-summary-\(UUID().uuidString)")!
        let center = FakeNotificationCenter()
        let now = Date()
        func schedule() {
            DailySummary.schedule(tasks: [], now: now, defaults: defaults, center: center)
            let drained = expectation(description: "drained")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { drained.fulfill() }
            wait(for: [drained], timeout: 2)
        }
        // 关闭且没有排过：不发删除请求。
        schedule()
        XCTAssertTrue(center.removes.isEmpty)

        defaults.set(true, forKey: NotificationSettings.enabledKey)
        defaults.set(true, forKey: DailySummary.enabledKey)
        schedule()
        schedule()
        XCTAssertEqual(center.adds, 1, "同一条摘要不重复添加")

        defaults.set(false, forKey: DailySummary.enabledKey)
        schedule()
        XCTAssertEqual(center.removes, [DailySummary.identifier])
    }
}

@MainActor
final class TransientSyncErrorTests: XCTestCase {
    func testClassifiesTemporaryNetworkErrors() {
        XCTAssertTrue(SyncController.isTransient("Error Domain=NSURLErrorDomain Code=-1003 \"A server with the specified hostname could not be found.\""))
        XCTAssertTrue(SyncController.isTransient("The request timed out."))
        XCTAssertTrue(SyncController.isTransient("The Internet connection appears to be offline."))
        XCTAssertTrue(SyncController.isTransient("Network is unavailable"))
        XCTAssertFalse(SyncController.isTransient("WebDAV request failed: HTTP 401"))
        XCTAssertFalse(SyncController.isTransient("Failed to merge sync snapshot: invalid"))
        XCTAssertTrue(SyncController.friendly("Error Domain=NSURLErrorDomain Code=-1003").hasPrefix("连不上服务器"))
    }
}

/// 读取时总是报「找不到服务器」的云端。
final class UnreachableTransport: NSObject, SyncBlobTransport, @unchecked Sendable {
    func close() {}
    func read(path: String, completionHandler: @escaping (SyncBlob?, (any Error)?) -> Void) {
        completionHandler(nil, NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost,
                                       userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
    }
    func write(path: String, bytes: KotlinByteArray, condition: any SyncWriteCondition, completionHandler: @escaping ((any Error)?) -> Void) {
        completionHandler(nil)
    }
    func ensureCollection(path: String, completionHandler: @escaping (KotlinBoolean?, (any Error)?) -> Void) {
        completionHandler(KotlinBoolean(bool: true), nil)
    }
}

@MainActor
final class SyncWakeTests: XCTestCase {
    func testFirstTemporaryFailureIsNotShownAsFailedButARepeatIs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-wake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let device = MacCoreContainer(databaseURL: directory.appendingPathComponent("a.db"), deviceId: "device-a")
        let defaults = UserDefaults(suiteName: "deadliner-wake-\(UUID().uuidString)")!
        let sync = SyncController(database: device.database, defaults: defaults) {}
        defer {
            sync.stop()
            device.close()
            try? FileManager.default.removeItem(at: directory)
        }
        sync.configureForTesting(transport: UnreachableTransport())

        try await waitUntil(timeout: 10) { sync.log.count >= 1 }
        XCTAssertEqual(sync.log.first?.message, SyncController.transientMessage)
        if case .failed = sync.status { XCTFail("第一次临时错误不应显示为失败") }

        // Core 在前台会自动重试；连续第二次仍失败才显示。
        try await waitUntil(timeout: 20) { sync.log.count >= 2 }
        guard case .failed(let message) = sync.status else { return XCTFail("连续失败应显示为失败：\(sync.status)") }
        XCTAssertTrue(message.hasPrefix("连不上服务器"), message)
    }

    func testWakeGraceHoldsSyncUntilItEnds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-wake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let device = MacCoreContainer(databaseURL: directory.appendingPathComponent("a.db"), deviceId: "device-a")
        let defaults = UserDefaults(suiteName: "deadliner-wake-\(UUID().uuidString)")!
        let sync = SyncController(database: device.database, defaults: defaults) {}
        let cloud = InMemoryBlobTransport()
        defer {
            sync.stop()
            device.close()
            try? FileManager.default.removeItem(at: directory)
        }
        sync.configureForTesting(transport: cloud)
        try await waitUntil(timeout: 10) { sync.log.count >= 1 }
        let synced = sync.log.count

        sync.willSleep()
        sync.didWake(grace: 1)
        sync.syncNow()
        // 等待期内网络视为不可用：这次同步不会连接云端。
        try await waitUntil(timeout: 5) { sync.log.count > synced }
        XCTAssertEqual(sync.log.first?.succeeded, false)
        // 等待期结束后恢复，Core 在前台立即同步一次。
        try await waitUntil(timeout: 10) { sync.log.first?.succeeded == true && sync.log.count > synced + 1 }
    }

    private struct Timeout: Error {}

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw Timeout() }
            try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

final class DiagnosticsRotationTests: XCTestCase {
    func testOversizedLogIsMovedAside() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-diag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let big = directory.appendingPathComponent(Diagnostics.fileNames[0])
        let small = directory.appendingPathComponent(Diagnostics.fileNames[1])
        try Data(count: Diagnostics.maxFileBytes + 1).write(to: big)
        try Data("x".utf8).write(to: small)
        Diagnostics.rotate(in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: big.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: big.path + ".1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: small.path))
    }
}
