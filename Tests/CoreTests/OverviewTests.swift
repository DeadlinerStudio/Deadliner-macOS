import SwiftUI
import XCTest
import Shared
@testable import DeadlinerTestHost

/// 第二期：概览数据来自 Core 的 OverviewViewModel，并截图检查三个分区。
@MainActor
final class OverviewTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var overview: OverviewStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-overview-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(
            databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
            deviceId: "macos-test-device"
        )
    }

    override func tearDown() async throws {
        overview?.stop()
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testOverviewCountsComeFromCore() async throws {
        let commands = TaskCommands(database: container.database) {}
        let now = Date()
        var done = TaskDraft()
        done.title = "示例已完成"
        done.dueAt = now.addingTimeInterval(3600 * 4)
        let doneId = try commands.save(done)
        try commands.toggleComplete(doneId)
        var pending = TaskDraft()
        pending.title = "示例待完成"
        pending.dueAt = now.addingTimeInterval(86400 * 2)
        _ = try commands.save(pending)
        var overdue = TaskDraft()
        overdue.title = "示例逾期"
        overdue.dueAt = now.addingTimeInterval(-3600 * 30)
        _ = try commands.save(overdue)

        overview = OverviewStore(database: container.database)
        overview.refresh()
        try await waitUntil { !self.overview.isLoading }

        XCTAssertNil(overview.errorMessage)
        XCTAssertEqual(overview.today.completed, 1)
        XCTAssertEqual(overview.history.completed, 1)
        XCTAssertEqual(overview.history.total, 3)
        XCTAssertEqual(overview.history.overdue, 1)
        XCTAssertEqual(overview.history.onTime, 1)
        XCTAssertEqual(overview.periods.map(\.count).reduce(0, +), 1)
        XCTAssertFalse(overview.contribution.isEmpty)
        XCTAssertEqual(overview.contribution.map(\.completed).reduce(0, +), 1)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-01"
        let thisMonth = formatter.string(from: now)
        overview.loadMonth(thisMonth)
        try await waitUntil { self.overview.month != nil || self.overview.monthError != nil }
        XCTAssertNil(overview.monthError)
        XCTAssertEqual(overview.month?.review.monthStart, thisMonth)

        let today = Calendar.current.startOfDay(for: now)
        let custom = DateRange(start: today.addingTimeInterval(-86400 * 20), end: today.addingTimeInterval(86400 * 10))
        overview.loadRange(custom)
        try await waitUntil { self.overview.range != nil || self.overview.rangeError != nil }

        let pages: [(String, OverviewSection, String, TrendRange)] = [
            ("stats-all", .stats, OverviewRange.all, .week),
            ("stats-month", .stats, thisMonth, .week),
            ("trends-week", .trends, OverviewRange.all, .week),
            ("trends-month", .trends, OverviewRange.all, .month),
            ("trends-year", .trends, OverviewRange.all, .year),
            ("stats-custom", .stats, OverviewRange.custom, .week),
            ("trends-custom", .trends, OverviewRange.all, .custom),
        ]
        for (name, section, range, trend) in pages {
            for scheme in [ColorScheme.light, .dark] {
                try capture(
                    OverviewContent(store: overview, section: section, range: .constant(range), trend: .constant(trend), layout: .double,
                                    customRange: custom)
                        .deadlinerTheme()
                        .environment(\.colorScheme, scheme),
                    scheme: scheme,
                    name: "overview-\(name)-\(scheme == .dark ? "dark" : "light")"
                )
            }
        }
    }

    func testCustomRangeComesFromCore() async throws {
        let commands = TaskCommands(database: container.database) {}
        var done = TaskDraft()
        done.title = "示例范围内完成"
        done.dueAt = Date().addingTimeInterval(3600)
        let doneId = try commands.save(done)
        try commands.toggleComplete(doneId)
        var future = TaskDraft()
        future.title = "示例未来到期"
        future.dueAt = Date().addingTimeInterval(86400 * 20)
        _ = try commands.save(future)

        overview = OverviewStore(database: container.database)
        let today = Calendar.current.startOfDay(for: Date())
        let selection = DateRange(start: today.addingTimeInterval(-86400 * 10), end: today.addingTimeInterval(86400 * 30))
        overview.loadRange(selection)
        try await waitUntil { self.overview.range != nil || self.overview.rangeError != nil }
        let detail = try XCTUnwrap(overview.range)
        XCTAssertEqual(detail.review.daily.count, selection.dayCount)
        XCTAssertEqual(detail.distribution.completed, 1)
        XCTAssertEqual(detail.distribution.onTime, 1)
        XCTAssertEqual(detail.periods.map(\.count).reduce(0, +), 1)
        XCTAssertTrue(detail.extendsIntoFuture)
        XCTAssertEqual(detail.elapsedDaily.count, 11)
        XCTAssertEqual(detail.review.completedTitles, ["示例范围内完成"])
    }

    func testDateRangeEncodingPresetsAndMonthPaging() throws {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let range = DateRange(start: end, end: start)  // 顺序颠倒也能纠正
        XCTAssertEqual(range.start, start)
        XCTAssertEqual(range.dayCount, 81)
        XCTAssertEqual(range.encoded, "2026-10-12|2026-12-31")
        XCTAssertEqual(DateRange.decode(range.encoded), range)
        XCTAssertNil(DateRange.decode("bad"))
        XCTAssertEqual(DateRange.isoString(range.endExclusive()), "2027-01-01")
        XCTAssertTrue(range.contains(end.addingTimeInterval(3600 * 23)))
        XCTAssertFalse(range.contains(range.endExclusive()))

        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let presets = DateRange.presets(now: now)
        XCTAssertEqual(presets.map(\.range.dayCount), [7, 30, 92, 365])
        XCTAssertEqual(OverviewRange.month("2026-11-01", offset: -1, now: now), "2026-10-01")
        XCTAssertEqual(OverviewRange.month("2026-01-01", offset: -1, now: now), "2025-12-01")
        XCTAssertNil(OverviewRange.month("2026-11-01", offset: 1, now: now))
    }

    func testHeatmapWeeksStartOnMonday() {
        // 2026-10-28 是周三：前面空出周一、周二。
        let days = (28...31).map { OverviewStore.DayCount(date: "2026-10-\($0)", completed: 1) }
            + (1...2).map { OverviewStore.DayCount(date: "2026-11-0\($0)", completed: 0) }
        let weeks = OverviewHeatmapCard.weeks(days)
        XCTAssertEqual(weeks.count, 2)
        XCTAssertNil(weeks[0][0])
        XCTAssertNil(weeks[0][1])
        XCTAssertEqual(weeks[0][2]?.date, "2026-10-28")
        XCTAssertEqual(weeks[0][6]?.date, "2026-11-01")
        XCTAssertEqual(weeks[1][0]?.date, "2026-11-02")
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
    }

    func testMetricFormatting() {
        XCTAssertEqual(OverviewMetricsCard.percent(66.6), "67%")
        XCTAssertEqual(OverviewMetricsCard.pointDelta(10), "+10%")
        XCTAssertNil(OverviewMetricsCard.pointDelta(0.1))
        XCTAssertEqual(OverviewMetricsCard.minutes(45), "45 分钟")
        XCTAssertEqual(OverviewMetricsCard.minutes(90), "1.5 小时")
        XCTAssertEqual(OverviewMetricsCard.minutes(2880), "2.0 天")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("等待超时") }
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func capture<V: View>(_ view: V, scheme: ColorScheme, name: String) throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1300, height: 950)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        let url = output.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT \(url.path)")
    }
}
