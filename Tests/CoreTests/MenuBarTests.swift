import XCTest
@testable import DeadlinerTestHost

/// 菜单栏汇总：今天到期、逾期、下一个截止与设置编码。
final class MenuBarSummaryTests: XCTestCase {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))! }

    private func task(_ id: String, due: TimeInterval?, state: TaskItem.State = .active) -> TaskItem {
        TaskItem(id: id, title: id, note: "", startAt: nil, dueAt: due.map { now.addingTimeInterval($0) }, state: state,
                 isStarred: false, categoryId: nil, subtaskDone: 0, subtaskTotal: 0, createdAt: now.addingTimeInterval(-86400), updatedAt: nil)
    }

    func testCountsAndOrdering() {
        let tasks = [
            task("later-today", due: 3600 * 5),
            task("overdue", due: -3600),
            task("tomorrow", due: 86400 + 3600),
            task("no-due", due: nil),
            task("done", due: 3600, state: .completed),
        ]
        let summary = MenuBarSummary.make(tasks: tasks, habits: [], today: HabitDay(date: "x", completed: 1, total: 3, fraction: 1 / 3),
                                          focusTodaySeconds: 4800, focusDays: [], now: now)
        XCTAssertEqual(summary.activeCount, 4)
        XCTAssertEqual(summary.overdue, 1)
        XCTAssertEqual(summary.dueToday, 1)
        XCTAssertEqual(summary.pending, 2)
        XCTAssertEqual(summary.upcoming.map(\.id), ["overdue", "later-today", "tomorrow"])
        XCTAssertEqual(summary.next?.id, "later-today")
        XCTAssertEqual(summary.value(for: .habits, now: now), "1/3")
        XCTAssertEqual(summary.value(for: .focus, now: now), "1h20")
        XCTAssertEqual(summary.value(for: .next, now: now), "5小时")
    }

    func testSettingsEncoding() {
        XCTAssertEqual(StatusField.decode("overdue,focus"), [.overdue, .focus])
        XCTAssertEqual(StatusField.decode(""), StatusField.defaults)
        XCTAssertEqual(PanelSection.decode(nil), PanelSection.defaults)
        XCTAssertEqual(PanelSection.decode(""), [])
        XCTAssertEqual(PanelSection.encode([.tasks, .sync]), "tasks,sync")
    }
}
