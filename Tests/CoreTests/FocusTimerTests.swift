import SwiftUI
import XCTest
import Shared
@testable import DeadlinerTestHost

/// 专注计时：经过 Core 的 IosFocusTimerStateBridge；规则与 iOS、Android 相同。
@MainActor
final class FocusTimerTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var timer: FocusTimerStore!
    private var recorded = 0

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-focus-timer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
                                     deviceId: "macos-test-device")
        recorded = 0
        timer = FocusTimerStore(database: container.database, alarm: FocusAlarmPortCompanion.shared.NONE) { [unowned self] in
            recorded += 1
        }
        timer.start()
        try await waitUntil { self.timer.isLoaded && !self.timer.isBusy }
    }

    override func tearDown() async throws {
        // Core 在后台线程读数据库：等它空闲后再关闭，避免查询落在已关闭的数据库上。
        if let timer { try await waitUntil { !timer.isBusy } }
        timer?.stop()
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeTask(_ title: String) throws -> String {
        var draft = TaskDraft()
        draft.title = title
        draft.dueAt = Date().addingTimeInterval(86400)
        return try TaskCommands(database: container.database) {}.save(draft)
    }

    func testCountdownPauseResumeFinishAndCompleteTask() async throws {
        let taskId = try makeTask("示例专注任务")
        timer.startTask(taskId, minutes: 25)
        try await waitUntil { self.timer.running != nil && !self.timer.isBusy }
        let running = try XCTUnwrap(timer.running)
        XCTAssertEqual(running.targetId, taskId)
        XCTAssertFalse(running.isHabit)
        XCTAssertTrue(running.isCountdown)
        XCTAssertTrue(running.isRunning)
        XCTAssertEqual(running.plannedSeconds, 25 * 60)
        XCTAssertEqual(running.remainingSeconds ?? 0, 25 * 60, accuracy: 2)

        // 同一时间只能有一个专注。
        let other = try makeTask("示例另一个任务")
        timer.startTask(other, minutes: nil)
        try await waitUntil { self.timer.errorMessage != nil && !self.timer.isBusy }
        XCTAssertEqual(timer.running?.targetId, taskId)

        timer.pause()
        try await waitUntil { self.timer.running?.isRunning == false && !self.timer.isBusy }
        XCTAssertTrue(timer.running?.canResume == true)
        timer.resume()
        try await waitUntil { self.timer.running?.isRunning == true && !self.timer.isBusy }

        // Core 按整秒计算，不满 1 秒的专注不会保存（与手机相同）。
        try await _Concurrency.Task.sleep(nanoseconds: 1_200_000_000)
        timer.finish()
        try await waitUntil { self.timer.result != nil }
        XCTAssertNil(timer.errorMessage)
        XCTAssertNil(timer.running)
        let result = try XCTUnwrap(timer.result)
        XCTAssertEqual(result.title, "示例专注任务")
        XCTAssertTrue(result.canCompleteTask)
        XCTAssertFalse(result.taskCompleted)
        XCTAssertGreaterThan(recorded, 0)
        XCTAssertEqual(container.database.focusSessions.list().filter { !$0.isDeleted }.count, 1)

        timer.completeSavedTask()
        try await waitUntil { self.timer.result?.taskCompleted == true }
        XCTAssertEqual(container.database.tasks.find(uid: taskId)?.state.name, "COMPLETED")
    }

    func testCompletingTimedTaskAsksFirstThenResolves() async throws {
        let taskId = try makeTask("示例计时中完成")
        timer.startTask(taskId, minutes: nil)
        try await waitUntil { self.timer.running != nil && !self.timer.isBusy }

        let commands = TaskCommands(database: container.database) {}
        var conflict: TimerConflict?
        commands.onTimerConflict = { conflict = $0 }
        try commands.toggleComplete(taskId)
        let pending = try XCTUnwrap(conflict)
        XCTAssertEqual(pending.title, "示例计时中完成")
        XCTAssertFalse(pending.delete)
        XCTAssertEqual(container.database.tasks.find(uid: taskId)?.state.name, "ACTIVE")  // 还没有改

        var message: String?? = .none
        timer.resolveTaskChange(taskId, action: pending.action, delete: false) { message = .some($0) }
        try await waitUntil { message != nil }
        XCTAssertNil(message!)
        XCTAssertEqual(container.database.tasks.find(uid: taskId)?.state.name, "COMPLETED")
        try await waitUntil { self.timer.running == nil }
    }

    func testDiscardSavesNothingAndHabitArchiveIsGuarded() async throws {
        var habit = HabitDraft()
        habit.name = "示例专注习惯"
        let habitCommands = HabitCommands(database: container.database) {}
        let habitId = try habitCommands.save(habit)

        timer.startHabit(habitId, minutes: 10)
        try await waitUntil { self.timer.running != nil && !self.timer.isBusy }
        XCTAssertTrue(timer.running?.isHabit == true)
        XCTAssertTrue(timer.isTiming(habit: habitId))

        // 正在计时的习惯不能直接归档（Core 会抛出异常），交给界面确认。
        var conflict: TimerConflict?
        habitCommands.isTiming = { [timer] in timer!.isTiming(habit: $0) }
        habitCommands.onTimerConflict = { conflict = $0 }
        try habitCommands.archive(habitId)
        XCTAssertEqual(conflict?.isHabit, true)

        timer.discard()
        try await waitUntil { self.timer.running == nil }
        XCTAssertNil(timer.result)
        XCTAssertEqual(container.database.focusSessions.list().filter { !$0.isDeleted }.count, 0)
    }

    /// 计时中、结果和菜单栏面板计时行的截图（编辑器是系统表单，ImageRenderer 画不出来），浅色 / 深色，供人工检查。
    func testRenderTimerSnapshots() async throws {
        let taskId = try makeTask("示例：写周报")
        timer.selectTask(taskId)
        func save<V: View>(_ view: V, _ name: String, width: CGFloat, height: CGFloat) throws {
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: view.environment(\.focusTimer, timer).deadlinerTheme()
                    .environment(\.colorScheme, scheme).frame(width: width, height: height)
                    .background(scheme == .dark ? Color.black : Color.white))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("deadliner-snapshots/focus-\(name)-\(scheme == .dark ? "dark" : "light").png")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            }
        }
        timer.startTask(taskId, minutes: 25)
        try await waitUntil { self.timer.running != nil && !self.timer.isBusy }
        try await _Concurrency.Task.sleep(nanoseconds: 1_200_000_000)
        try save(FocusRunningView(timer: timer, running: try XCTUnwrap(timer.running)).padding(20), "running", width: 320, height: 380)
        try save(FocusPanelTimerRow(timer: timer, running: try XCTUnwrap(timer.running)) {}, "panel-row", width: 340, height: 56)
        timer.finish()
        try await waitUntil { self.timer.result != nil }
        try save(FocusResultView(timer: timer, result: try XCTUnwrap(timer.result)) {}.padding(20), "result", width: 320, height: 380)
    }

    func testClockAndMessages() {
        XCTAssertEqual(FocusTimerStore.clock(0), "00:00")
        XCTAssertEqual(FocusTimerStore.clock(25 * 60), "25:00")
        XCTAssertEqual(FocusTimerStore.clock(3600 + 5 * 60 + 9), "1:05:09")
        XCTAssertNil(FocusTimerStore.message(for: "APPLIED"))
        XCTAssertEqual(FocusTimerStore.message(for: "TIMER_ALREADY_ACTIVE"), "已经有一个正在进行的专注，请先结束它")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("等待 Core 状态超时") }
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
