import XCTest
import Shared
@testable import Deadliner_for_macOS

/// 习惯编辑与专注记录：保存经过 Core，非法输入在交给 Core 之前被拦下（不会因 Kotlin 异常崩溃）。
@MainActor
final class HabitCommandsTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var commands: HabitCommands!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-habit-commands-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(
            databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
            deviceId: "macos-test-device"
        )
        commands = HabitCommands(database: container.database) {}
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testCreateAndEditRoundTrip() throws {
        var draft = HabitDraft()
        draft.name = " 背单词 "
        draft.note = "每天 50 个"
        draft.colorHex = "#10B981"
        draft.weekdaysMask = 0b001_0101 // 一、三、五
        draft.goalWindow = .week
        draft.targetCount = 3
        draft.reminderEnabled = true
        draft.reminderTime = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date())!
        let uid = try commands.save(draft)

        let habit = try XCTUnwrap(container.database.habits.find(uid: uid))
        XCTAssertEqual(habit.name, "背单词")
        XCTAssertEqual(habit.schedule.kind, HabitScheduleKind.weeklyDays)
        XCTAssertEqual(habit.schedule.weekdaysMask?.intValue, 0b001_0101)
        XCTAssertEqual(habit.goal.window, HabitGoalWindow.week)
        XCTAssertEqual(habit.goal.targetCount, 3)
        XCTAssertEqual(habit.reminder?.localTime, "07:30")
        XCTAssertEqual(habit.color.map { HabitItem.hex(fromArgb: $0.intValue) }, "#10B981")
        XCTAssertEqual(habit.status, HabitStatus.active)

        var edited = try XCTUnwrap(commands.draft(for: uid))
        XCTAssertEqual(edited.name, "背单词")
        XCTAssertEqual(edited.weekdaysMask, 0b001_0101)
        XCTAssertEqual(HabitCommands.localTime(edited.reminderTime), "07:30")
        edited.trackingMode = .quantity
        edited.unit = "个"
        edited.defaultIncrement = 10
        edited.targetCount = 50
        edited.goalWindow = .scheduledDay
        edited.reminderEnabled = false
        try commands.save(edited)

        let updated = try XCTUnwrap(container.database.habits.find(uid: uid))
        XCTAssertEqual(updated.tracking.mode, HabitTrackingMode.quantity)
        XCTAssertEqual(updated.tracking.unit, "个")
        XCTAssertEqual(updated.tracking.defaultIncrement, 10)
        XCTAssertNil(updated.reminder)
        XCTAssertEqual(updated.createdAt, habit.createdAt)
    }

    func testAlgorithmAndOnceSchedules() throws {
        var review = HabitDraft()
        review.name = "复习"
        review.scheduleKind = .algorithm
        let reviewUid = try commands.save(review)
        XCTAssertEqual(container.database.habits.find(uid: reviewUid)?.schedule.algorithmKey, HabitAlgorithms.shared.EBBINGHAUS_CLASSIC_V1)
        XCTAssertNil(container.database.habits.find(uid: reviewUid)?.schedule.weekdaysMask)

        var once = HabitDraft()
        once.name = "体检"
        once.scheduleKind = .once
        let onceUid = try commands.save(once)
        XCTAssertEqual(container.database.habits.find(uid: onceUid)?.schedule.kind, HabitScheduleKind.once)
    }

    func testInvalidDraftsAreRejectedBeforeReachingCore() {
        var draft = HabitDraft()
        draft.name = "无效"
        draft.weekdaysMask = 0
        XCTAssertThrowsError(try commands.save(draft)) { XCTAssertEqual($0 as? HabitCommandError, .invalid("请至少选择一天")) }

        draft.weekdaysMask = 1
        draft.endOn = Calendar.current.date(byAdding: .day, value: -1, to: draft.startOn)
        XCTAssertThrowsError(try commands.save(draft))

        draft.endOn = nil
        draft.trackingMode = .quantity
        draft.defaultIncrement = 0
        XCTAssertThrowsError(try commands.save(draft))

        draft.defaultIncrement = 1
        draft.targetCount = 0
        XCTAssertThrowsError(try commands.save(draft))

        draft.targetCount = 1
        draft.name = "  "
        XCTAssertThrowsError(try commands.save(draft))
        XCTAssertTrue(container.database.habits.list().isEmpty)
    }

    func testArchiveAndDelete() throws {
        var draft = HabitDraft()
        draft.name = "冥想"
        let uid = try commands.save(draft)
        try commands.archive(uid)
        XCTAssertEqual(container.database.habits.find(uid: uid)?.status, HabitStatus.archived)
        commands.delete(uid)
        XCTAssertNil(commands.draft(for: uid))
    }

    func testFocusStoreReadsEmptyDatabase() {
        let focus = FocusStore(database: container.database)
        focus.refresh()
        XCTAssertEqual(focus.allTime, .init(totalSeconds: 0, sessionCount: 0))
        XCTAssertTrue(focus.sessions.isEmpty)
        XCTAssertEqual(FocusTexts.duration(5400), "1小时30分")
        XCTAssertEqual(FocusTexts.duration(1500), "25分钟")
    }
}
