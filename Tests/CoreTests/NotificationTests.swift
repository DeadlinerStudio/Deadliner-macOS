import XCTest
import Shared
@testable import DeadlinerTestHost

/// 第二期：通知的时间与类型由 Core 计算，Mac 端只转成系统通知（测试中写入内存，不碰通知中心）。
@MainActor
final class NotificationTests: XCTestCase {
    private final class RecordingSink: NotificationSink {
        private let lock = NSLock()
        private var _items: [PlannedNotification] = []
        var items: [PlannedNotification] { lock.withLock { _items } }
        func replaceAll(with notifications: [PlannedNotification]) { lock.withLock { _items = notifications } }
        func removeAll() { lock.withLock { _items = [] } }
    }

    private var directory: URL!
    private var container: MacCoreContainer!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-notification-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(
            databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
            deviceId: "macos-test-device"
        )
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// 23:59 截止的任务改在白天提醒；同一时刻的多条任务提醒合并成一条。
    func testEndOfDayRemindersMoveToDaytimeAndMerge() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 10))!
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))! }
        func item(_ id: String, _ kind: String, fire: Date, due: Date?) -> PlannedNotification {
            PlannedNotification(id: "deadliner.\(id)", ownerUid: id, kind: kind, title: "示例\(id)",
                                body: MacNotificationGateway.body(kind: kind, dueAt: "") ?? "", fireAt: fire, dueAt: due)
        }
        let items = [
            item("a", "TASK_DUE", fire: at(13, 23, 59), due: at(13, 23, 59)),
            item("b", "TASK_DUE", fire: at(13, 23, 59), due: at(13, 23, 59)),
            item("a", "TASK_NEARBY", fire: at(12, 23, 59), due: at(13, 23, 59)),
            item("c", "TASK_DUE", fire: at(13, 15, 0), due: at(13, 15, 0)),        // 不是 23:59：不动
            item("d", "TASK_DUE", fire: at(11, 23, 59), due: at(11, 23, 59)),      // 今天 9:00 已过：不补发
            item("h", "HABIT_DUE", fire: at(12, 0, 0), due: nil),                  // 习惯不动
        ]
        let shaped = NotificationShaping.apply(items, options: .init(daytime: true, daytimeMinutes: 9 * 60), now: now)
        XCTAssertEqual(shaped.count, 4)
        let merged = shaped.first { $0.id.hasPrefix("deadliner.group.TASK_DUE") }
        XCTAssertEqual(merged?.title, "今天有 2 项任务截止")
        XCTAssertEqual(merged?.body, "示例a、示例b")
        XCTAssertEqual(merged?.fireAt, at(13, 9, 0))
        let nearby = shaped.first { $0.kind == "TASK_NEARBY" }
        XCTAssertEqual(nearby?.fireAt, at(12, 9, 0))
        XCTAssertEqual(nearby?.body, "明天 23:59 截止")
        XCTAssertEqual(shaped.first { $0.ownerUid == "c" }?.fireAt, at(13, 15, 0))
        XCTAssertNil(shaped.first { $0.ownerUid == "d" })
        XCTAssertEqual(shaped.first { $0.kind == "HABIT_DUE" }?.fireAt, at(12, 0, 0))

        // 关闭后保持 Core 的时间，只合并同一时刻的提醒。
        let plain = NotificationShaping.apply(items, options: .init(daytime: false), now: now)
        XCTAssertEqual(plain.first { $0.id.hasPrefix("deadliner.group.TASK_DUE") }?.title, "2 项任务已到截止时间")
        XCTAssertEqual(plain.count, 5)
    }

    func testCorePlansTaskReminders() throws {
        let sink = RecordingSink()
        var policy = NotificationPolicy(taskRealtime: false, taskNearby: true, taskDue: true, habitMode: HabitNotificationMode.due)
        _ = container.database.configureNotificationUpdates(
            gateway: MacNotificationGateway(sink: sink, habitsEnabled: { true }),
            policyProvider: { policy },
            interactionsProvider: { NotificationInteractionState(taskResults: [], dismissedHabitOccurrences: []) }
        )
        let commands = TaskCommands(database: container.database) {}
        var draft = TaskDraft()
        draft.title = "示例提醒"
        draft.dueAt = Date().addingTimeInterval(86400 * 3)
        let uid = try commands.save(draft)

        // 保存后 Core 的提交监听会自动重新计算。
        let kinds = Set(sink.items.filter { $0.ownerUid == uid }.map(\.kind))
        XCTAssertEqual(kinds, ["TASK_NEARBY", "TASK_DUE"])
        let due = try XCTUnwrap(sink.items.first { $0.kind == "TASK_DUE" })
        XCTAssertEqual(due.title, "示例提醒")
        XCTAssertEqual(due.body, "已到截止时间")
        XCTAssertEqual(due.fireAt.timeIntervalSince1970, draft.dueAt!.timeIntervalSince1970, accuracy: 60)
        XCTAssertTrue(due.id.hasPrefix("deadliner."))

        // 完成后不再提醒。
        try commands.toggleComplete(uid)
        XCTAssertTrue(sink.items.filter { $0.ownerUid == uid }.isEmpty)

        // 关闭「提前一天」后只剩到期提醒。
        policy = NotificationPolicy(taskRealtime: false, taskNearby: false, taskDue: true, habitMode: HabitNotificationMode.due)
        var other = TaskDraft()
        other.title = "示例提醒二"
        other.dueAt = Date().addingTimeInterval(86400 * 3)
        let otherId = try commands.save(other)
        XCTAssertEqual(sink.items.filter { $0.ownerUid == otherId }.map(\.kind), ["TASK_DUE"])
    }

    /// 同步合并在后台线程提交后，Core 会在那个线程调用策略回调。回调若被当作主线程专用，
    /// Swift 会直接终止应用（2026-11-01 的崩溃）。
    func testProvidersCanBeCalledOffMainThread() async throws {
        let sink = RecordingSink()
        _ = container.database.configureNotificationUpdates(
            gateway: MacNotificationGateway(sink: sink, habitsEnabled: { true }),
            policyProvider: NotificationController.policyProvider,
            interactionsProvider: NotificationController.interactionsProvider
        )
        nonisolated(unsafe) let database = container.database
        let ranOffMain = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                database.triggerNotificationInfoUpdate(force: true)
                done.resume(returning: !Thread.isMainThread)
            }
        }
        XCTAssertTrue(ranOffMain)
    }

    func testDisabledSettingsPlanNothing() {
        let defaults = UserDefaults(suiteName: "notification-tests-\(UUID().uuidString)")!
        let policy = NotificationSettings.policy(defaults)
        XCTAssertFalse(policy.taskNearby)
        XCTAssertFalse(policy.taskDue)
        XCTAssertFalse(policy.taskRealtime)
        XCTAssertFalse(NotificationSettings.habitsEnabled(defaults))
        defaults.set(true, forKey: NotificationSettings.enabledKey)
        XCTAssertTrue(NotificationSettings.policy(defaults).taskDue)
        XCTAssertTrue(NotificationSettings.habitsEnabled(defaults))
        XCTAssertNil(MacNotificationGateway.body(kind: "FOCUS_RESULT", dueAt: ""))
    }
}
