import SwiftUI
import XCTest
@testable import DeadlinerTestHost

/// 完成时机只在 Mac 上推算：超前 / 提前 / 按时 / 逾期互不重叠。
final class CompletionTimingTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func task(start: Date? = nil, due: Date?, done: Date?, state: TaskItem.State = .completed) -> TaskItem {
        TaskItem(id: "t", title: "示例", note: "", startAt: start, dueAt: due, state: state, isStarred: false, categoryId: nil,
                 subtaskDone: 0, subtaskTotal: 0, createdAt: date(1, 9), updatedAt: nil, completedAt: done)
    }

    func testFourKindsDoNotOverlap() {
        // 开始前完成：超前，即使也比截止早很多天，也不算提前。
        XCTAssertEqual(CompletionTiming.of(task(start: date(10, 9), due: date(14, 23, 59), done: date(9, 20)), calendar: calendar), .ahead)
        // 开始后、比截止日早一天以上：提前。
        XCTAssertEqual(CompletionTiming.of(task(start: date(8, 9), due: date(14, 23, 59), done: date(12, 10)), calendar: calendar), .early)
        // 截止当天、截止前：按时（不算提前）。
        XCTAssertEqual(CompletionTiming.of(task(due: date(14, 23, 59), done: date(14, 8)), calendar: calendar), .onTime)
        // 截止后：逾期。
        XCTAssertEqual(CompletionTiming.of(task(due: date(14, 12), done: date(14, 13)), calendar: calendar), .late)
        // 没有截止时间：只能是超前，否则没有完成时机。
        XCTAssertEqual(CompletionTiming.of(task(start: date(10, 9), due: nil, done: date(9, 9)), calendar: calendar), .ahead)
        XCTAssertNil(CompletionTiming.of(task(due: nil, done: date(9, 9)), calendar: calendar))
        // 未完成或没有完成时间（例如完成后又取消）不算。
        XCTAssertNil(CompletionTiming.of(task(due: date(14, 12), done: nil), calendar: calendar))
        XCTAssertNil(CompletionTiming.of(task(due: date(14, 12), done: date(9, 9), state: .active), calendar: calendar))
        // 归档后仍按完成时间计算。
        XCTAssertEqual(CompletionTiming.of(task(due: date(14, 12), done: date(9, 9), state: .archived), calendar: calendar), .early)
    }

    func testDaysBeforeDueUseLocalDates() {
        // 13 日 23:00 完成、14 日 08:00 截止：只差 9 小时，但按日期早一天。
        let t = task(due: date(14, 8), done: date(13, 23))
        XCTAssertEqual(CompletionTiming.of(t, calendar: calendar), .early)
        XCTAssertEqual(CompletionTiming.daysBeforeDue(t, calendar: calendar), 1)
    }

    func testCountsOnlyCompletionsInRange() {
        let tasks = [
            task(start: date(10, 9), due: date(14, 12), done: date(9, 9)),   // 超前，范围内
            task(due: date(14, 12), done: date(12, 9)),                      // 提前，范围内
            task(due: date(14, 12), done: date(15, 9)),                      // 逾期，范围外
            task(due: nil, done: date(9, 9)),                                // 没有完成时机
        ]
        let counts = CompletionTiming.counts(tasks, from: date(1, 0), to: date(15, 0))
        XCTAssertEqual(counts, [.ahead: 1, .early: 1])
    }

    func testCardStatusAndText() {
        let now = date(9, 21)
        let ahead = task(start: date(10, 9), due: date(14, 12), done: date(9, 20))
        XCTAssertEqual(TaskStatus.indicator(ahead, now: now), .completedAhead)
        XCTAssertEqual(TaskStatus.remainingText(ahead, now: now), "超前完成")
        let early = task(due: date(12, 12), done: date(9, 20))
        XCTAssertEqual(TaskStatus.indicator(early, now: now), .completedEarly)
        XCTAssertEqual(TaskStatus.remainingText(early, now: now), "提前 3 天完成")
        // 按时、逾期完成仍是「已完成」的卡片颜色。
        let late = task(due: date(9, 12), done: date(9, 20))
        XCTAssertEqual(TaskStatus.indicator(late, now: now), .completed)
        XCTAssertEqual(TaskStatus.remainingText(late, now: now), "逾期完成")
        XCTAssertEqual(TaskStatus.remainingText(task(due: date(9, 23), done: date(9, 20)), now: now), "已完成")
    }

    func testNewKindsHaveCustomizableColors() {
        let raw = StatusColorSettings.updating("", .completedAhead, to: Color(hex: 0x123456))
        XCTAssertEqual(raw, "completedAhead=#123456")
        var palette = DeadlinerPalette.light
        palette.statusOverrides = StatusColorSettings.decode(raw)
        XCTAssertEqual(StatusColorSettings.hex(IndicatorStatus.completedAhead.solid(palette)), "#123456")
        XCTAssertTrue(IndicatorStatus.allCases.contains(.completedEarly))
    }
}
