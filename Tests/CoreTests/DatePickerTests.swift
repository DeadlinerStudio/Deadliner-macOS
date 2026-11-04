import SwiftUI
import XCTest
@testable import DeadlinerTestHost

/// 自定义日期选择器的日期计算；固定柏林时区与「现在」，并截图检查面板。
@MainActor
final class DatePickerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testQuickDaysRelativeToWednesday() {
        let now = date(2026, 11, 4, 15, 30) // 周三
        XCTAssertEqual(DeadlinerDateMath.day(.today, now: now, calendar: calendar), date(2026, 11, 4))
        XCTAssertEqual(DeadlinerDateMath.day(.tomorrow, now: now, calendar: calendar), date(2026, 11, 5))
        XCTAssertEqual(DeadlinerDateMath.day(.weekend, now: now, calendar: calendar), date(2026, 11, 7))
        XCTAssertEqual(DeadlinerDateMath.day(.nextMonday, now: now, calendar: calendar), date(2026, 11, 9))
    }

    func testQuickDaysAtWeekEdges() {
        let monday = date(2026, 11, 2, 8)
        XCTAssertEqual(DeadlinerDateMath.day(.nextMonday, now: monday, calendar: calendar), date(2026, 11, 9))
        XCTAssertEqual(DeadlinerDateMath.day(.weekend, now: monday, calendar: calendar), date(2026, 11, 7))
        let saturday = date(2026, 11, 7, 22)
        XCTAssertEqual(DeadlinerDateMath.day(.weekend, now: saturday, calendar: calendar), date(2026, 11, 7))
        XCTAssertEqual(DeadlinerDateMath.day(.nextMonday, now: saturday, calendar: calendar), date(2026, 11, 9))
        let sunday = date(2026, 11, 8, 10)
        XCTAssertEqual(DeadlinerDateMath.day(.weekend, now: sunday, calendar: calendar), date(2026, 11, 8))
        XCTAssertEqual(DeadlinerDateMath.day(.nextMonday, now: sunday, calendar: calendar), date(2026, 11, 9))
        // 跨年：2026-12-31 周四
        XCTAssertEqual(DeadlinerDateMath.day(.tomorrow, now: date(2026, 12, 31, 23, 59), calendar: calendar), date(2027, 1, 1))
    }

    func testCombineKeepsTimeAcrossDST() {
        // 2026-10-25 柏林夏令时结束
        let combined = DeadlinerDateMath.combine(day: date(2026, 10, 25), time: date(2026, 10, 1, 23, 59), calendar: calendar)
        XCTAssertEqual(combined, date(2026, 10, 25, 23, 59))
    }

    func testMonthGridStartsOnMonday() {
        let grid = DeadlinerDateMath.monthGrid(for: date(2026, 11, 18), calendar: DeadlinerDateMath.mondayFirst(calendar))
        XCTAssertEqual(grid.count, 6)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        // 2026-11-01 是周日：第一行前六格空
        XCTAssertEqual(grid[0].prefix(6).compactMap { $0 }.count, 0)
        XCTAssertEqual(grid[0][6], date(2026, 11, 1))
        XCTAssertEqual(grid[1][0], date(2026, 11, 2))
        let days = grid.flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.last, date(2026, 11, 30))
        XCTAssertEqual(grid[5][0], date(2026, 11, 30))
    }

    func testMonthGridFebruaryStartingMonday() {
        // 2027-02-01 是周一，共 28 天，正好四行
        let grid = DeadlinerDateMath.monthGrid(for: date(2027, 2, 10), calendar: calendar)
        XCTAssertEqual(grid[0][0], date(2027, 2, 1))
        XCTAssertEqual(grid[3][6], date(2027, 2, 28))
        XCTAssertTrue(grid[4].allSatisfy { $0 == nil } && grid[5].allSatisfy { $0 == nil })
    }

    func testClampDateAndTime() {
        let bounds = DatePickerBounds.between(date(2026, 11, 4, 12), date(2026, 11, 10, 18))
        XCTAssertEqual(DeadlinerDateMath.clamp(date(2026, 11, 4, 9), to: bounds, calendar: calendar), date(2026, 11, 4, 12))
        XCTAssertEqual(DeadlinerDateMath.clamp(date(2026, 11, 12, 9), to: bounds, calendar: calendar), date(2026, 11, 10, 18))
        XCTAssertEqual(DeadlinerDateMath.clamp(date(2026, 11, 6, 9), to: bounds, calendar: calendar), date(2026, 11, 6, 9))
        XCTAssertEqual(DeadlinerDateMath.clamp(date(2020, 1, 1), to: .unbounded, calendar: calendar), date(2020, 1, 1))
    }

    func testClampDateOnlyComparesWholeDays() {
        let bounds = DatePickerBounds.through(date(2026, 11, 4, 15, 30))
        // 同一天晚些时候仍在范围内，只选日期时不改
        XCTAssertEqual(DeadlinerDateMath.clamp(date(2026, 11, 4, 23), to: bounds, mode: .date, calendar: calendar), date(2026, 11, 4, 23))
        XCTAssertEqual(DeadlinerDateMath.clamp(date(2026, 11, 9, 8), to: bounds, mode: .date, calendar: calendar), date(2026, 11, 4, 8))
        let from = DatePickerBounds.from(date(2026, 11, 4, 15))
        XCTAssertEqual(DeadlinerDateMath.clamp(date(2026, 11, 1), to: from, mode: .date, calendar: calendar), date(2026, 11, 4))
        XCTAssertTrue(DeadlinerDateMath.isSelectable(date(2026, 11, 4), bounds: bounds, calendar: calendar))
        XCTAssertFalse(DeadlinerDateMath.isSelectable(date(2026, 11, 5), bounds: bounds, calendar: calendar))
        XCTAssertFalse(DeadlinerDateMath.isSelectable(date(2026, 11, 3), bounds: from, calendar: calendar))
    }

    func testParseTyping() {
        XCTAssertTrue(DeadlinerDateMath.parseTime("9:30")! == (9, 30))
        XCTAssertTrue(DeadlinerDateMath.parseTime("9：05")! == (9, 5))
        XCTAssertTrue(DeadlinerDateMath.parseTime("0930")! == (9, 30))
        XCTAssertTrue(DeadlinerDateMath.parseTime("930")! == (9, 30))
        XCTAssertTrue(DeadlinerDateMath.parseTime("18")! == (18, 0))
        XCTAssertTrue(DeadlinerDateMath.parseTime(" 23.59 ")! == (23, 59))
        XCTAssertNil(DeadlinerDateMath.parseTime("24:00"))
        XCTAssertNil(DeadlinerDateMath.parseTime("12:60"))
        XCTAssertNil(DeadlinerDateMath.parseTime("abc"))
        XCTAssertNil(DeadlinerDateMath.parseTime(""))
    }

    func testFieldLabel() {
        let now = date(2026, 11, 4, 10)
        XCTAssertEqual(DeadlinerDateMath.label(date(2026, 11, 4, 23, 59), mode: .dateAndTime, now: now, calendar: calendar), "今天 23:59")
        XCTAssertEqual(DeadlinerDateMath.label(date(2026, 11, 5), mode: .date, now: now, calendar: calendar), "明天")
        XCTAssertEqual(DeadlinerDateMath.label(date(2026, 11, 9, 9), mode: .dateAndTime, now: now, calendar: calendar), "11月9日 周一 09:00")
        XCTAssertEqual(DeadlinerDateMath.label(date(2027, 1, 3), mode: .date, now: now, calendar: calendar), "2027年1月3日 周日")
        XCTAssertEqual(DeadlinerDateMath.label(date(2027, 1, 3, 7, 5), mode: .time, now: now, calendar: calendar), "07:05")
    }

    /// 浅色、深色各渲染一次面板和范围表单，输出到临时目录供人工查看。
    func testRenderPanelSnapshots() async throws {
        let now = Date()
        let due = DeadlinerDateMath.combine(day: DeadlinerDateMath.day(.tomorrow, now: now), time: DeadlinerDateMath.setTime(hour: 23, minute: 59, on: now))
        let today = Calendar.current.startOfDay(for: now)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let panel = DeadlinerDatePickerPanel(selection: .constant(due), components: .dateAndTime, bounds: .unbounded,
                                                 allowsNone: true, defaultValue: { now }, now: now) {}
            try await capture(VStack(spacing: 16) {
                panel
                HStack {
                    DeadlinerDatePicker(selection: .constant(due))
                    DeadlinerDatePicker(selection: .constant(nil as Date?))
                    DeadlinerDatePicker(selection: .constant(due), components: .time)
                }
            }.padding(16).background(PaletteBackground()).deadlinerTheme().environment(\.colorScheme, scheme), scheme: scheme,
                              name: "datepicker-panel-\(suffix)", size: CGSize(width: 360, height: 560))
            let range = DateRange(start: today.addingTimeInterval(-86400 * 12), end: today.addingTimeInterval(86400 * 3))
            try await capture(DateRangeSheet(initial: range, now: now, onDone: { _ in }, onCancel: {})
                .background(PaletteBackground()).deadlinerTheme().environment(\.colorScheme, scheme), scheme: scheme,
                              name: "datepicker-range-\(suffix)", size: CGSize(width: 640, height: 480))
        }
    }

    /// 截图时托管视图是透明的，补上页面底色。
    private struct PaletteBackground: View {
        @Environment(\.palette) private var t
        var body: some View { t.pageBg }
    }

    private func capture<V: View>(_ view: V, scheme: ColorScheme, name: String, size: CGSize) async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        try await _Concurrency.Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        let url = output.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT \(url.path)")
    }
}
