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
