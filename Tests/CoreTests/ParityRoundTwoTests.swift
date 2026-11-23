import XCTest
import Shared
import UserNotifications
@testable import DeadlinerTestHost

/// 第二轮补齐的功能：自动归档、通知按钮与稍后提醒、检查更新、自定义提示词、鼓励语句。
@MainActor
final class ParityRoundTwoTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var commands: TaskCommands!
    private var changes = 0

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-parity2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName), deviceId: "parity-test")
        changes = 0
        commands = TaskCommands(database: container.database) { [unowned self] in changes += 1 }
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func task(_ title: String, due: Date? = nil) throws -> String {
        var draft = TaskDraft()
        draft.title = title
        draft.dueAt = due
        return try commands.save(draft)
    }

    /// 在指定时刻完成任务（Core 用 occurredAt 记录完成时刻）。
    private func complete(_ uid: String, at date: Date) {
        _ = container.database.tasks.applyAction(uid: uid, action: TaskAction.markComplete, occurredAt: CoreClock.instant(date))
    }

    // MARK: - 自动归档

    func testAutoArchiveMovesOnlyTasksCompletedLongerAgo() throws {
        let now = Date()
        let old = try task("示例：完成很久")
        let recent = try task("示例：刚完成")
        let active = try task("示例：进行中")
        let abandoned = try task("示例：已放弃")
        complete(old, at: now.addingTimeInterval(-8.5 * 86400))
        complete(recent, at: now.addingTimeInterval(-2.5 * 86400))
        _ = container.database.tasks.applyAction(uid: abandoned, action: TaskAction.markGiveUp, occurredAt: CoreClock.instant(now.addingTimeInterval(-30 * 86400)))
        changes = 0

        XCTAssertEqual(commands.archiveExpired(days: 7, now: now), 1)
        XCTAssertEqual(changes, 1, "一次归档多条也只通知一次刷新")
        XCTAssertEqual(commands.item(old)?.state, .archived)
        XCTAssertEqual(commands.item(recent)?.state, .completed)
        XCTAssertEqual(commands.item(active)?.state, .active)
        XCTAssertEqual(commands.item(abandoned)?.state, .abandoned)

        XCTAssertEqual(commands.archiveExpired(days: 7, now: now), 0)
        XCTAssertEqual(changes, 1, "没有需要归档的任务时不刷新")
        XCTAssertEqual(commands.archiveExpired(days: 1, now: now), 1)
        XCTAssertEqual(commands.item(recent)?.state, .archived)
    }

    func testAutoArchiveCountsWholeDaysLikeAndroid() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func done(_ days: Double) -> TaskItem {
            TaskItem(id: "\(days)", title: "示例", note: "", startAt: nil, dueAt: nil, state: .completed, isStarred: false, categoryId: nil,
                     subtaskDone: 0, subtaskTotal: 0, createdAt: nil, updatedAt: nil, completedAt: now.addingTimeInterval(-days * 86400))
        }
        // 安卓：Duration.toDays() > N，即满 N+1 天才归档。
        XCTAssertEqual(AutoArchive.due([done(7.9), done(8.0), done(3)], days: 7, now: now), ["8.0"])
        let defaults = UserDefaults(suiteName: "deadliner-archive-\(UUID().uuidString)")!
        XCTAssertEqual(AutoArchive.settings(defaults).enabled, false)
        XCTAssertEqual(AutoArchive.settings(defaults).days, 7)
    }

    // MARK: - 通知按钮与稍后提醒

    func testTaskRemindersCarryActionButtons() {
        let fire = Date().addingTimeInterval(3600)
        let requests = UserNotificationSink.requests(for: [
            PlannedNotification(id: "deadliner.a", ownerUid: "a", kind: "TASK_DUE", title: "示例", body: "到期", fireAt: fire),
            PlannedNotification(id: "deadliner.h", ownerUid: "h", kind: "HABIT_DUE", title: "示例习惯", body: "该打卡了", fireAt: fire),
        ], now: Date())
        XCTAssertEqual(requests.first { $0.identifier == "deadliner.a" }?.content.categoryIdentifier, TaskNotificationActions.categoryId)
        XCTAssertEqual(requests.first { $0.identifier == "deadliner.h" }?.content.categoryIdentifier, "")

        // 之前排的没有按钮：比较时视为不同，会重新添加一次。
        let old = UNMutableNotificationContent()
        old.title = "示例"; old.body = "到期"; old.userInfo = ["ownerUid": "a", "kind": "TASK_DUE"]
        let stale = UNNotificationRequest(identifier: "deadliner.a", content: old, trigger: requests[0].trigger)
        XCTAssertEqual(UserNotificationSink.diff(pending: [stale], desired: [requests[0]]).add.count, 1)

        XCTAssertEqual(TaskNotificationActions.action(for: TaskNotificationActions.complete), .complete)
        XCTAssertEqual(TaskNotificationActions.action(for: TaskNotificationActions.later), .later)
        XCTAssertEqual(TaskNotificationActions.action(for: TaskNotificationActions.delete), .delete)
        XCTAssertNil(TaskNotificationActions.action(for: UNNotificationDefaultActionIdentifier))
    }

    func testLaterDelayIsHalfTheRemainingTimeAtLeastOneHour() {
        let now = Date()
        XCTAssertEqual(TaskNotificationActions.laterDelayHours(dueAt: now.addingTimeInterval(10 * 3600), now: now), 5)
        XCTAssertEqual(TaskNotificationActions.laterDelayHours(dueAt: now.addingTimeInterval(90 * 60), now: now), 1)
        XCTAssertEqual(TaskNotificationActions.laterDelayHours(dueAt: now.addingTimeInterval(-3600), now: now), 1)
        XCTAssertEqual(TaskNotificationActions.laterDelayHours(dueAt: nil, now: now), 1)
    }

    func testSnoozeSchedulesOnceAndIsPrunedAfterCompletion() throws {
        let now = Date()
        let uid = try task("示例：稍后提醒", due: now.addingTimeInterval(6.5 * 3600))
        let center = FakeNotificationCenter()
        let controller = NotificationController(database: container.database) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "示例：稍后提醒"
        content.userInfo = ["ownerUid": uid, "kind": "TASK_DUE"]

        controller.snooze(uid, content: content, now: now, center: center)
        let request = try XCTUnwrap(center.request(TaskNotificationActions.snoozeId(uid)))
        XCTAssertEqual((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 3 * 3600)
        XCTAssertEqual(request.content.categoryIdentifier, TaskNotificationActions.categoryId)

        // 任务还在进行中：保留；完成后：去掉。
        controller.pruneSnoozes(center: center)
        drain()
        XCTAssertTrue(center.identifiers.contains(TaskNotificationActions.snoozeId(uid)))
        try commands.toggleComplete(uid)
        controller.pruneSnoozes(center: center)
        drain()
        XCTAssertFalse(center.identifiers.contains(TaskNotificationActions.snoozeId(uid)))

        // 已完成的任务不再排稍后提醒。
        controller.snooze(uid, content: content, now: now, center: center)
        XCTAssertNil(center.request(TaskNotificationActions.snoozeId(uid)))
    }

    private func drain() {
        let done = expectation(description: "drain")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { DispatchQueue.main.async { done.fulfill() } }
        wait(for: [done], timeout: 2)
    }

    // MARK: - 检查更新、提示词、鼓励语句

    func testVersionComparison() {
        XCTAssertEqual(UpdateChecker.compare("0.1.0", "v0.1.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compare("0.1.0", "v0.2.0"), .orderedAscending)
        XCTAssertEqual(UpdateChecker.compare("0.10.0", "0.9.9"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compare("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compare("1.2.0-beta", "1.2.1"), .orderedAscending)
        let page = URL(string: "https://example.com/release")!
        XCTAssertEqual(UpdateChecker.outcome(latestTag: "v0.2.0", page: page, current: "0.1.0"), .available(version: "0.2.0", page: page))
        XCTAssertEqual(UpdateChecker.outcome(latestTag: "v0.1.0", page: page, current: "0.1.0"), .upToDate(current: "0.1.0"))
    }

    func testCustomPromptIsPlacedBeforeTheText() {
        XCTAssertEqual(LifiSettings.extractionInput("明天交报告", prompt: ""), "明天交报告")
        XCTAssertEqual(LifiSettings.extractionInput("明天交报告", prompt: "默认 23:59 截止"), "默认 23:59 截止\n\n明天交报告")
    }

    func testQuotesRotateEveryMinute() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(MotivationalQuotes.chinese.count, 20)
        XCTAssertEqual(MotivationalQuotes.english.count, 20)
        XCTAssertEqual(MotivationalQuotes.quote(at: base), MotivationalQuotes.quote(at: base.addingTimeInterval(30)))
        XCTAssertNotEqual(MotivationalQuotes.quote(at: base, from: MotivationalQuotes.chinese),
                          MotivationalQuotes.quote(at: base.addingTimeInterval(60), from: MotivationalQuotes.chinese))
    }
}
