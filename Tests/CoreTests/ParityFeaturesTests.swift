import SwiftUI
import XCTest
import Shared
@testable import DeadlinerTestHost

/// 与安卓 / iOS 对齐的六项：完成动画、分享链接、每日摘要、临近提醒提前时间、分类详情、显示大小。
@MainActor
final class ParityFeaturesTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-parity-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
                                     deviceId: "macos-test-device")
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: - 分享链接

    /// 按安卓 `DeadlinerURLScheme` 的算法（JDK 的 PBKDF2 / AES-GCM / Deflate）生成的链接，内容是安卓 `DDLItem` 的 JSON。
    private let androidLink = "https://www.aritxonly.top/deadliner/share?v=1&k=1&m=pass&s=YtmXVXMdwH5sPphJtZWcVg&i=200000&d=ARtInGJsdymmecs0Tit_9NH-081GFqscgqHjdTnw9xn-qTgw4gL3Yoa6ofXuoo6sDJghj65ejvZhPQL-cwd1QHpdkCpKPi_VNAzxGlgSQ_qJjyvG8jOUmQ6-bXhbPS4pQQcjig2tdoYG9_deWGCsvDAlQk-8nYrC02eQMCRpZa2PzkmCIhums1iMwdu7CT5vNV50GKEJ1vHRuHDNrgtys5rPdqIeHGpk--AcCuMfhDDd4kC4gBSy0SwFkSBCM-B1iDMzePPlX_GcDIeU8PS4bhczy1d48W5Q3GDNz-g4U7riNOLNldZ6UdGXQM187TU2z9cXHfPLwqQhekp1I5xnOv72YycMmDXA4zWf8TsAZLhoyMV1u82-XwMtn7QGGrNwXnCpKKI3Mgfx-wRpSvMrlQzHG8BI5LgnhOZI1zbQQeGaegrn"

    func testDecodesAndroidLink() throws {
        XCTAssertTrue(TaskShareLink.isLink(androidLink))
        let draft = try TaskShareLink.decode(androidLink)
        XCTAssertNil(draft.id)
        XCTAssertEqual(draft.title, "示例：交实验报告")
        XCTAssertEqual(draft.note, "第 3 题")
        XCTAssertTrue(draft.isStarred)
        XCTAssertEqual(draft.startAt, date(14, 9))
        XCTAssertEqual(draft.dueAt, date(20, 23, 59))
        XCTAssertEqual(draft.subtasks.map(\.content), ["画图", "写结论"])
        XCTAssertEqual(draft.subtasks.map(\.isCompleted), [true, false])
        XCTAssertFalse(draft.subtasks.contains { $0.id == "s1" }, "导入后用新的子任务 ID")
    }

    func testRoundTripAndWritesLinkForAndroidCheck() throws {
        var draft = TaskDraft()
        draft.id = "original"
        draft.title = "  示例：周报  "
        draft.note = "备注"
        draft.startAt = date(15, 8, 30)
        draft.dueAt = date(16, 18)
        draft.isStarred = true
        draft.subtasks = [.init(id: "a", content: "收集数据", isCompleted: true), .init(id: "b", content: "写总结", isCompleted: false)]
        let link = try TaskShareLink.encode(draft, now: date(14, 12))
        XCTAssertTrue(link.hasPrefix(TaskShareLink.prefix + "?v=1&k=1&m=pass&s="))
        let item = try TaskShareLink.decodeItem(link)
        XCTAssertEqual(item.name, "示例：周报")
        XCTAssertEqual(item.startTime, "2026-11-15T08:30")
        XCTAssertEqual(item.endTime, "2026-11-16T18:00")
        XCTAssertEqual(item.subTasks.map(\.sortOrder), [0, 1])
        let back = try TaskShareLink.decode(link)
        XCTAssertEqual(back.title, "示例：周报")
        XCTAssertEqual(back.dueAt, draft.dueAt)
        XCTAssertEqual(back.subtasks.map(\.content), ["收集数据", "写总结"])
        // 供人工用 JDK（安卓相同算法）解开验证。
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots/share-link.txt")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try link.write(to: url, atomically: true, encoding: .utf8)
    }

    func testRejectsBadLinks() {
        XCTAssertThrowsError(try TaskShareLink.decode("https://example.com/share?v=1")) { XCTAssertEqual($0 as? TaskShareLink.LinkError, .notALink) }
        XCTAssertThrowsError(try TaskShareLink.decode(TaskShareLink.prefix + "?v=2&m=pass")) { XCTAssertEqual($0 as? TaskShareLink.LinkError, .unsupported) }
        let tampered = androidLink.replacingOccurrences(of: "d=ARtI", with: "d=ARtJ")
        XCTAssertThrowsError(try TaskShareLink.decode(tampered)) { XCTAssertEqual($0 as? TaskShareLink.LinkError, .corrupted) }
    }

    func testLocalTimeFormat() {
        XCTAssertEqual(TaskShareLink.localString(date(3, 7, 5)), "2026-11-03T07:05")
        XCTAssertEqual(TaskShareLink.parseLocal("2026-11-03T07:05:30.123"), Calendar.current.date(byAdding: .second, value: 30, to: date(3, 7, 5)))
        XCTAssertNil(TaskShareLink.parseLocal(""))
    }

    // MARK: - 完成动画

    func testCompletionCallbackOnlyWhenCompletingActiveTask() throws {
        let commands = TaskCommands(database: container.database) {}
        var completed: [String] = []
        commands.onCompleted = { completed.append($0) }
        var draft = TaskDraft()
        draft.title = "示例任务"
        draft.dueAt = date(20, 12)
        let id = try commands.save(draft)
        try commands.toggleComplete(id)      // 完成
        try commands.toggleComplete(id)      // 取消完成：不播放
        try commands.toggleGiveUp(id)        // 放弃：不播放
        XCTAssertEqual(completed, [id])
        XCTAssertEqual(CelebrationOverlay.makeParticles(count: 10).count, 10)
    }

    // MARK: - 每日摘要

    func testDailySummaryCountsAndTime() {
        func task(_ id: String, due: Date?, state: TaskItem.State = .active) -> TaskItem {
            TaskItem(id: id, title: id, note: "", startAt: nil, dueAt: due, state: state, isStarred: false, categoryId: nil,
                     subtaskDone: 0, subtaskTotal: 0, createdAt: nil, updatedAt: nil)
        }
        let now = date(14, 10)
        XCTAssertEqual(DailySummary.nextFire(minutes: 9 * 60, now: now), date(15, 9))
        XCTAssertEqual(DailySummary.nextFire(minutes: 18 * 60, now: now), date(14, 18))
        let tasks = [task("逾期", due: date(13, 12)), task("今天", due: date(15, 20)), task("以后", due: date(18, 9)),
                     task("无截止", due: nil), task("已完成", due: date(15, 10), state: .completed)]
        let counts = DailySummary.counts(tasks, at: date(15, 9))
        XCTAssertEqual(counts, .init(dueToday: 1, overdue: 1, inProgress: 2))
        XCTAssertEqual(DailySummary.title(counts), "今日任务概览 - 1 个任务今日到期")
        XCTAssertEqual(DailySummary.title(.init()), "今日任务概览")
        XCTAssertEqual(DailySummary.body(counts), "🔥逾期 1 ｜ ⌛️进行中 2")
    }

    // MARK: - 临近提醒提前时间

    func testNearbyRemindersFollowCustomHours() {
        let now = date(14, 10)
        let due = PlannedNotification(id: "deadliner.k1", ownerUid: "t1", kind: "TASK_DUE", title: "示例", body: "已到截止时间",
                                      fireAt: date(16, 15), dueAt: date(16, 15))
        let coreNearby = PlannedNotification(id: "deadliner.k0", ownerUid: "t1", kind: "TASK_NEARBY", title: "示例", body: "",
                                             fireAt: date(15, 15), dueAt: date(16, 15))
        let threeHours = MacNotificationGateway.derivingNearby([due, coreNearby], options: .init(nearby: true, due: true, nearbyHours: 3), now: now)
        XCTAssertEqual(threeHours.map(\.kind), ["TASK_NEARBY", "TASK_DUE"])
        XCTAssertEqual(threeHours.first?.fireAt, date(16, 12))
        XCTAssertTrue(threeHours.first?.body.hasPrefix("还有 3 小时到期") == true)
        XCTAssertEqual(threeHours.first?.id, "deadliner.nearby.k1")
        // 只要临近提醒：去掉到期提醒；已经过了的临近时间不排。
        let onlyNearby = MacNotificationGateway.derivingNearby([due], options: .init(nearby: true, due: false, nearbyHours: 72), now: now)
        XCTAssertTrue(onlyNearby.isEmpty)
        XCTAssertEqual(MacNotificationGateway.derivingNearby([due], options: .init(nearby: false, due: true, nearbyHours: 24), now: now), [due])
        XCTAssertEqual(TaskReminderOptions.phrase(hours: 48), "2 天")
        XCTAssertEqual(TaskReminderOptions.phrase(hours: 6), "6 小时")

        // 23:59 截止：提前 2 天的临近提醒移到那天的白天；提前不到一天的保持原时间。
        let endOfDay = PlannedNotification(id: "deadliner.k2", ownerUid: "t2", kind: "TASK_DUE", title: "示例2", body: "已到截止时间",
                                           fireAt: date(18, 23, 59), dueAt: date(18, 23, 59))
        let twoDays = NotificationShaping.apply(
            MacNotificationGateway.derivingNearby([endOfDay], options: .init(nearby: true, due: false, nearbyHours: 48), now: now),
            options: .init(daytime: true, daytimeMinutes: 9 * 60), now: now)
        XCTAssertEqual(twoDays.first?.fireAt, date(16, 9))
        XCTAssertEqual(twoDays.first?.body, "2 天后 23:59 截止")
        let sameDay = NotificationShaping.apply(
            MacNotificationGateway.derivingNearby([endOfDay], options: .init(nearby: true, due: false, nearbyHours: 3), now: now),
            options: .init(daytime: true, daytimeMinutes: 9 * 60), now: now)
        XCTAssertEqual(sameDay.first?.fireAt, date(18, 20, 59))
    }

    func testPolicyAsksCoreOnlyForDueReminders() {
        let defaults = UserDefaults(suiteName: "deadliner-parity-\(UUID().uuidString)")!
        defaults.set(true, forKey: NotificationSettings.enabledKey)
        defaults.set(false, forKey: NotificationSettings.taskDueKey)
        defaults.set(6, forKey: NotificationSettings.nearbyHoursKey)
        let policy = NotificationSettings.policy(defaults)
        XCTAssertFalse(policy.taskNearby)
        XCTAssertTrue(policy.taskDue, "临近提醒从到期提醒派生，所以仍向 Core 要到期提醒")
        XCTAssertEqual(NotificationSettings.taskReminders(defaults), .init(nearby: true, due: false, nearbyHours: 6))
    }

    // MARK: - 分类详情

    func testCategoryContents() throws {
        let categories = CategoryCommands(database: container.database) {}
        let tasks = TaskCommands(database: container.database) {}
        let habits = HabitCommands(database: container.database) {}
        let work = try categories.create(name: "示例工作", iconKey: "briefcase", colorHex: "#3B82F6")
        var draft = TaskDraft()
        draft.title = "示例任务 A"
        draft.categoryId = work
        let a = try tasks.save(draft)
        draft.title = "示例任务 B"
        draft.categoryId = nil
        _ = try tasks.save(draft)
        try tasks.toggleComplete(a)
        var habit = HabitDraft()
        habit.name = "示例习惯"
        habit.categoryId = work
        _ = try habits.save(habit)

        let contents = categories.contents(of: work)
        XCTAssertEqual(contents.tasks.map(\.title), ["示例任务 A"])
        XCTAssertEqual(contents.tasks.first?.state, .completed)
        XCTAssertEqual(contents.habits.map(\.name), ["示例习惯"])
        XCTAssertEqual(categories.contents(of: nil).tasks.map(\.title), ["示例任务 B"])
        // 分类删除后，其中的任务归到「未分类」。
        try categories.delete(id: work)
        XCTAssertEqual(Set(categories.contents(of: nil).tasks.map(\.title)), ["示例任务 A", "示例任务 B"])
    }

    // MARK: - 显示大小

    func testDisplayScaleOptions() {
        XCTAssertEqual(DisplayScale.allCases.map(\.title), ["更紧凑", "稍紧凑", "标准", "稍大", "更大"])
        XCTAssertEqual(DisplayScale.standard.factor, 1)
        XCTAssertTrue(DisplayScale.allCases.map(\.factor) == DisplayScale.allCases.map(\.factor).sorted())
    }
}
