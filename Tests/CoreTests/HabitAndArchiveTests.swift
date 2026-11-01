import XCTest
import Shared
@testable import DeadlinerTestHost

/// 第五步验收：习惯页的状态与打卡来自 Core，归档页的读取与恢复经过 Core。
@MainActor
final class HabitAndArchiveTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var habits: HabitListStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-habit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(
            databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
            deviceId: "macos-test-device"
        )
    }

    override func tearDown() async throws {
        habits?.stop()
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testCheckOffHabitTogglesThroughCore() async throws {
        let uid = insertHabit(name: "早起", mode: .checkOff, target: 1)
        habits = HabitListStore(database: container.database)
        habits.start()
        try await waitUntil { self.habits.dailyHabits.contains { $0.id == uid } }

        var habit = try XCTUnwrap(habits.dailyHabits.first { $0.id == uid })
        XCTAssertTrue(habit.isDue)
        XCTAssertTrue(habit.canApplyPrimaryAction)
        XCTAssertEqual(habit.actionKind, .checkOff)
        XCTAssertFalse(habit.isCompleted)
        XCTAssertEqual(HabitTexts.side(habit), "每天")

        habits.applyPrimaryAction(habit)
        try await waitUntil { self.habits.dailyHabits.first { $0.id == uid }?.isCompleted == true }
        habit = try XCTUnwrap(habits.dailyHabits.first { $0.id == uid })
        XCTAssertEqual(habit.doneCount, 1)
        XCTAssertEqual(habits.selectedDay?.completed, 1)
        XCTAssertFalse(container.database.habits.records(habitUid: uid).isEmpty)

        // Core 规定：完成后再次执行主操作会清除本周期记录。
        habits.applyPrimaryAction(habit)
        try await waitUntil { self.habits.dailyHabits.first { $0.id == uid }?.isCompleted == false }
    }

    func testQuantityHabitAccumulatesDefaultIncrement() async throws {
        let uid = insertHabit(name: "喝水", mode: .quantity, target: 1000, unit: "ml", increment: 250)
        habits = HabitListStore(database: container.database)
        habits.start()
        try await waitUntil { self.habits.dailyHabits.contains { $0.id == uid } }

        var habit = try XCTUnwrap(habits.dailyHabits.first { $0.id == uid })
        XCTAssertEqual(habit.actionKind, .addQuantity)
        XCTAssertEqual(habit.actionAmount, 250)
        habits.applyPrimaryAction(habit)
        try await waitUntil { self.habits.dailyHabits.first { $0.id == uid }?.doneCount == 250 }
        habit = try XCTUnwrap(habits.dailyHabits.first { $0.id == uid })
        XCTAssertEqual(HabitTexts.progress(habit), "250/1000 ml")
        XCTAssertFalse(habit.isCompleted)
    }

    func testFutureDateCannotBeCheckedIn() async throws {
        let uid = insertHabit(name: "阅读", mode: .checkOff, target: 1)
        habits = HabitListStore(database: container.database)
        habits.start()
        try await waitUntil { !self.habits.week.isEmpty }
        let tomorrow = HabitDates.string(Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        guard habits.week.contains(where: { $0.date == tomorrow }) else { return } // 今天是本周最后一天时跳过
        habits.select(date: tomorrow)
        try await waitUntil { self.habits.selectedDate == tomorrow }
        let habit = try XCTUnwrap((habits.dailyHabits + habits.periodGoals).first { $0.id == uid })
        XCTAssertFalse(habit.canApplyPrimaryAction, "Core 不允许为未来日期打卡")
    }

    func testArchiveListsArchivedTasksAndRestoresHabits() throws {
        let commands = TaskCommands(database: container.database) {}
        let done = try commands.save(TaskDraft(title: "已完成并归档"))
        try commands.toggleComplete(done)
        try commands.archive(done)
        _ = try commands.save(TaskDraft(title: "进行中"))
        let habitUid = insertHabit(name: "冥想", mode: .checkOff, target: 1)
        _ = container.database.habits.applyStatusAction(uid: habitUid, action: HabitStatusAction.archive, occurredAt: CoreClock.now())

        let archive = ArchiveStore(database: container.database)
        archive.refresh()
        XCTAssertEqual(archive.tasks.map(\.title), ["已完成并归档"])
        XCTAssertEqual(archive.habits.map(\.name), ["冥想"])

        try archive.restoreHabit(habitUid)
        archive.refresh()
        XCTAssertTrue(archive.habits.isEmpty)
        try commands.unarchive(done)
        archive.refresh()
        XCTAssertTrue(archive.tasks.isEmpty)
    }

    func testScheduleTexts() {
        func habit(_ mask: Int?) -> HabitItem {
            HabitItem(id: "h", name: "h", note: "", colorHex: nil, categoryId: nil, doneCount: 0, targetCount: 1,
                      isCompleted: false, canApplyPrimaryAction: true, actionKind: .checkOff, actionAmount: 1, unit: nil,
                      goalWindow: .scheduledDay, scheduleKind: .weeklyDays, weekdaysMask: mask, isDue: true,
                      dueReason: "DUE", hintKind: nil, daysUntil: nil)
        }
        XCTAssertEqual(HabitTexts.schedule(habit(nil)), "每天")
        XCTAssertEqual(HabitTexts.schedule(habit(0b001_1111)), "工作日")
        XCTAssertEqual(HabitTexts.schedule(habit(0b001_0101)), "每周一、三、五")
        XCTAssertEqual(HabitItem.hex(fromArgb: Int(Int32(bitPattern: 0xFF3B82F6))), "#3B82F6")
    }

    // MARK: - Helpers

    private enum Mode { case checkOff, quantity }

    @discardableResult
    private func insertHabit(name: String, mode: Mode, target: Int32, unit: String? = nil, increment: Int32 = 1) -> String {
        let uid = PlatformIdentity.shared.doNewId()
        let now = CoreClock.now()
        let start = HabitDates.string(Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
        let habit = Habit_(
            uid: uid, name: name, description: nil, color: nil, iconKey: nil, categoryUid: nil,
            schedule: HabitSchedule(kind: HabitScheduleKind.weeklyDays, startOn: start, endOn: nil, weekdaysMask: KotlinInt(int: 0b111_1111), algorithmKey: nil),
            goal: HabitGoal(window: HabitGoalWindow.scheduledDay, targetCount: target),
            tracking: HabitTracking(mode: mode == .quantity ? HabitTrackingMode.quantity : HabitTrackingMode.checkOff, unit: unit, defaultIncrement: increment),
            status: HabitStatus.active, sortOrder: 0, reminder: nil, createdAt: now, updatedAt: now, isDeleted: false
        )
        container.database.habits.create(habit: habit)
        return uid
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("等待 Core 状态超时") }
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
