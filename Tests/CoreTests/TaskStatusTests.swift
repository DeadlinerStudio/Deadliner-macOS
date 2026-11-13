import SwiftUI
import XCTest
@testable import DeadlinerTestHost

final class TaskStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(state: TaskItem.State = .active, start: TimeInterval? = nil, due: TimeInterval?, created: TimeInterval = -86400 * 10) -> TaskItem {
        TaskItem(
            id: "t", title: "t", note: "", startAt: start.map { now.addingTimeInterval($0) },
            dueAt: due.map { now.addingTimeInterval($0) }, state: state, isStarred: false, categoryId: nil,
            subtaskDone: 0, subtaskTotal: 0, createdAt: now.addingTimeInterval(created), updatedAt: nil
        )
    }

    func testIndicatorStatus() {
        XCTAssertEqual(TaskStatus.indicator(task(due: nil), now: now), .undergo)
        XCTAssertEqual(TaskStatus.indicator(task(due: 86400 * 3), now: now), .undergo)
        XCTAssertEqual(TaskStatus.indicator(task(due: 3600), now: now), .near)
        XCTAssertEqual(TaskStatus.indicator(task(due: -60), now: now), .passed)
        XCTAssertEqual(TaskStatus.indicator(task(state: .completed, due: -60), now: now), .completed)
        XCTAssertEqual(TaskStatus.indicator(task(state: .abandoned, due: 60), now: now), .abandoned)
        XCTAssertEqual(TaskStatus.indicator(task(start: 3600, due: 7200), now: now), .notStarted)
        XCTAssertEqual(TaskStatus.indicator(task(start: -3600, due: 86400 * 3), now: now), .undergo)
        XCTAssertEqual(TaskStatus.indicator(task(state: .completed, start: 3600, due: 7200), now: now), .completed)
    }

    /// 进度动画只在新的一轮（打开 / 切回任务页）时全部重播，编辑保存时只换被编辑的那张。
    func testCardSweepKeys() {
        var sweep = CardSweep()
        XCTAssertEqual(sweep.key(for: "a"), "0-0")
        sweep.edited["a", default: 0] += 1
        XCTAssertEqual(sweep.key(for: "a"), "0-1")
        XCTAssertEqual(sweep.key(for: "b"), "0-0")  // 其他卡片不变
        sweep.generation += 1
        XCTAssertEqual(sweep.key(for: "b"), "1-0")  // 切回任务页：全部换新
    }

    func testCustomStatusColorsRoundTripAndReset() {
        var raw = StatusColorSettings.updating("", .passed, to: Color(hex: 0x12AB34))
        raw = StatusColorSettings.updating(raw, .notStarted, to: Color(hex: 0xFFFFFF))
        XCTAssertEqual(raw, "notStarted=#FFFFFF;passed=#12AB34")
        let decoded = StatusColorSettings.decode(raw + ";bogus=#000000;near=zzz")
        XCTAssertEqual(Set(decoded.keys), [.notStarted, .passed])
        XCTAssertEqual(StatusColorSettings.hex(decoded[.passed]!), "#12AB34")

        var palette = DeadlinerPalette.light
        palette.statusOverrides = decoded
        XCTAssertEqual(StatusColorSettings.hex(IndicatorStatus.passed.solid(palette)), "#12AB34")
        XCTAssertEqual(StatusColorSettings.hex(IndicatorStatus.near.solid(palette)),
                       StatusColorSettings.hex(IndicatorStatus.near.defaultColor(palette)))

        XCTAssertEqual(StatusColorSettings.updating(raw, .notStarted, to: nil), "passed=#12AB34")
        XCTAssertEqual(StatusColorSettings.updating("passed=#12AB34", .passed, to: nil), "")
    }

    func testRemainingProgressIsRemainingFraction() {
        XCTAssertEqual(TaskStatus.remainingProgress(task(due: 86400 * 10, created: -86400 * 10), now: now), 0.5, accuracy: 0.001)
        XCTAssertEqual(TaskStatus.remainingProgress(task(start: 3600, due: 7200), now: now), 1)
        XCTAssertEqual(TaskStatus.remainingProgress(task(due: -1), now: now), 0)
        XCTAssertEqual(TaskStatus.remainingProgress(task(due: nil), now: now), 0)
        XCTAssertEqual(TaskStatus.remainingProgress(task(state: .completed, due: 3600), now: now), 0)
    }

    func testRemainingText() {
        XCTAssertEqual(TaskStatus.remainingText(task(due: 86400 * 2 + 3600 * 5), now: now), "2天 5小时")
        XCTAssertEqual(TaskStatus.remainingText(task(due: 3600 * 3), now: now), "3小时")
        XCTAssertEqual(TaskStatus.remainingText(task(due: 600), now: now), "10分钟")
        XCTAssertEqual(TaskStatus.remainingText(task(due: -86400), now: now), "已逾期 1天")
        XCTAssertEqual(TaskStatus.remainingText(task(start: 7200, due: 86400), now: now), "2小时后开始")
        XCTAssertEqual(TaskStatus.remainingText(task(state: .completed, due: 60), now: now), "已完成")
        XCTAssertEqual(TaskStatus.remainingText(task(due: nil), now: now), "")
    }

    func testCoreDateFormats() {
        XCTAssertNotNil(CoreDates.parseLocal("2026-11-20T09:00:00"))
        XCTAssertNotNil(CoreDates.parseLocal("2026-11-20T09:00"))
        XCTAssertNil(CoreDates.parseLocal("2026-11-20"))
        XCTAssertNotNil(CoreDates.parseInstant("2026-10-31T08:39:12.345Z"))
        XCTAssertNotNil(CoreDates.parseInstant("2026-10-31T08:39:12Z"))
    }
}
