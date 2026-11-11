import XCTest
@testable import DeadlinerTestHost

/// 每日概览弹窗：每天第一次打开一次、固定时间一次；默认关闭。
@MainActor
final class DailyBriefTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "deadliner-brief-tests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testOffByDefaultThenOncePerDayAndFixedTime() {
        var shown = 0
        let controller = DailyBriefController(defaults: defaults) { shown += 1; return true }
        controller.check(now: at(11, 8))
        XCTAssertEqual(shown, 0)  // 默认关闭

        defaults.set(true, forKey: DailyBriefSettings.enabledKey)
        controller.check(now: at(11, 8))
        controller.check(now: at(11, 8, 30))
        XCTAssertEqual(shown, 1)  // 当天第一次打开只弹一次

        defaults.set(true, forKey: DailyBriefSettings.fixedTimeKey)
        defaults.set(18 * 60, forKey: DailyBriefSettings.fixedMinutesKey)
        controller.check(now: at(11, 17, 59))
        XCTAssertEqual(shown, 1)
        controller.check(now: at(11, 18))
        controller.check(now: at(11, 19))
        XCTAssertEqual(shown, 2)  // 固定时间到了弹一次

        controller.check(now: at(12, 7))
        XCTAssertEqual(shown, 3)  // 第二天重新开始
    }

    func testNotMarkedWhenWindowCannotOpenYet() {
        var ready = false
        var shown = 0
        defaults.set(true, forKey: DailyBriefSettings.enabledKey)
        let controller = DailyBriefController(defaults: defaults) { guard ready else { return false }; shown += 1; return true }
        controller.check(now: at(11, 8))
        XCTAssertEqual(shown, 0)
        ready = true
        controller.check(now: at(11, 8, 1))
        XCTAssertEqual(shown, 1)
    }

    func testOngoingTasksAreStartedActiveSortedByDue() {
        let now = at(11, 12)
        func task(_ id: String, start: Date?, due: Date?, state: TaskItem.State = .active) -> TaskItem {
            TaskItem(id: id, title: id, note: "", startAt: start, dueAt: due, state: state, isStarred: false, categoryId: nil,
                     subtaskDone: 0, subtaskTotal: 0, createdAt: nil, updatedAt: nil)
        }
        let list = [task("later", start: nil, due: at(15, 23)), task("notYet", start: at(12, 9), due: at(13, 9)),
                    task("done", start: nil, due: at(11, 20), state: .completed), task("overdue", start: nil, due: at(10, 9)),
                    task("noDue", start: nil, due: nil)]
        XCTAssertEqual(DailyBriefView.ongoing(list, now: now).map(\.id), ["overdue", "later", "noDue"])
    }
}
