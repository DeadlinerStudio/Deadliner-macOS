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

        let pages: [(String, OverviewSection, String, TrendRange)] = [
            ("stats-all", .stats, OverviewRange.all, .week),
            ("stats-month", .stats, thisMonth, .week),
            ("trends-week", .trends, OverviewRange.all, .week),
            ("trends-month", .trends, OverviewRange.all, .month),
            ("trends-year", .trends, OverviewRange.all, .year),
        ]
        for (name, section, range, trend) in pages {
            for scheme in [ColorScheme.light, .dark] {
                try await capture(
                    OverviewContent(store: overview, section: section, range: .constant(range), trend: .constant(trend), layout: .double)
                        .deadlinerTheme()
                        .environment(\.colorScheme, scheme),
                    scheme: scheme,
                    name: "overview-\(name)-\(scheme == .dark ? "dark" : "light")"
                )
            }
        }
    }

    func testMonthStatusAndRefreshUseExclusiveCoreStates() async throws {
        let now = Date()
        let commands = TaskCommands(database: container.database) {}
        var draft = TaskDraft()
        draft.title = "月度逾期回归"
        draft.dueAt = now.addingTimeInterval(-1)
        let id = try commands.save(draft)
        overview = OverviewStore(database: container.database)
        overview.loadMonth(OverviewPeriod.key(OverviewPeriod.month()))
        try await waitUntil { !self.overview.monthLoading }
        XCTAssertEqual(overview.month?.distribution.overdue, 1)
        XCTAssertEqual(overview.month?.distribution.onTime, 0)
        XCTAssertEqual(overview.month?.distribution.total, 1)
        try commands.toggleComplete(id)
        overview.refresh()
        try await waitUntil { !self.overview.monthLoading && !self.overview.isLoading && !self.overview.annualLoading }
        XCTAssertEqual(overview.month?.distribution.completed, 1)
        XCTAssertEqual(overview.month?.distribution.overdue, 0)
        XCTAssertEqual(overview.annual.last?.date, OverviewPeriod.key(now))
        XCTAssertEqual(overview.annual.reduce(0) { $0 + $1.completed }, 1)
    }

    func testRangeLatestSelectionWinsAndFailureRecovers() async throws {
        overview = OverviewStore(database: container.database)
        let today = OverviewPeriod.key(Date())
        let tomorrow = OverviewPeriod.key(OverviewPeriod.calendar.date(byAdding: .day, value: 1, to: Date())!)
        overview.loadInterval(start: tomorrow, end: today)
        try await waitUntil { !self.overview.intervalLoading }
        XCTAssertNotNil(overview.intervalError)
        overview.loadInterval(start: "2020-01-01", end: "2021-01-01")
        overview.loadInterval(start: today, end: tomorrow)
        try await waitUntil { !self.overview.intervalLoading }
        XCTAssertNil(overview.intervalError)
        XCTAssertEqual(overview.interval?.daily.map(\.date), [today])
        try await _Concurrency.Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(overview.interval?.daily.map(\.date), [today])
    }

    func testSamePeriodComparisonHandlesShortMonthsAndZeroBaseline() {
        XCTAssertEqual(OverviewPeriod.comparison(current: [2, 3, 100], previous: [1, 4, 0], day: 2), "较上月同期持平")
        XCTAssertEqual(OverviewPeriod.comparison(current: [3], previous: [0], day: 31), "较上月同期新增 3 项")
        XCTAssertEqual(OverviewPeriod.comparison(current: [1, 1], previous: [1], day: 31), "较上月同期增长 100.0%")
        XCTAssertEqual(OverviewPeriod.comparison(current: [], previous: [2], day: 1), "较上月同期减少 100.0%")
    }

    func testMonthlyInsightCacheIsImmutableAndFailureDoesNotAutoRetry() throws {
        let month = OverviewPeriod.key(OverviewPeriod.shift(Date(), months: -1))
        let url = directory.appendingPathComponent(month + ".json")
        let cached = "{\"attempted\":true,\"result\":{\"month\":\"\(month)\",\"summary\":\"已保存洞察\",\"keywords\":[\"复盘\"]}}"
        try Data(cached.utf8).write(to: url)
        let insight = MonthlyInsightStore(directory: directory)
        var review = OverviewStore.MonthReview()
        review.monthStart = month
        insight.resolve(review: review, retry: true)
        XCTAssertEqual(insight.result?.summary, "已保存洞察")
        XCTAssertFalse(insight.loading)
        try Data("{\"attempted\":true}".utf8).write(to: url)
        insight.resolve(review: review)
        XCTAssertNil(insight.result)
        XCTAssertEqual(insight.error, "上次分析未完成，请点击重试")
        XCTAssertFalse(insight.loading)
    }

    func testDesktopWorkspaceSnapshots() async throws {
        let commands = TaskCommands(database: container.database) {}
        for i in 0..<12 {
            var task = TaskDraft()
            task.title = "桌面布局示例任务 \(i + 1)"
            task.dueAt = Date().addingTimeInterval(Double(i - 3) * 3600)
            let id = try commands.save(task)
            if i % 2 == 0 { try commands.toggleComplete(id) }
        }
        overview = OverviewStore(database: container.database)
        overview.refresh()
        overview.loadMonth(OverviewPeriod.key(OverviewPeriod.month()))
        try await waitUntil { !self.overview.isLoading && !self.overview.monthLoading }
        for tab in OverviewTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: "overview.desktop.tab")
            for width in [640.0, 1450.0] {
                try await capture(NavigationStack { OverviewWorkbench(store: overview) }.deadlinerTheme(), scheme: .light,
                            name: "desktop-\(tab.rawValue)-\(Int(width))", width: width)
            }
        }
        UserDefaults.standard.set(OverviewTab.dashboard.rawValue, forKey: "overview.desktop.tab")
        try await capture(NavigationStack { OverviewWorkbench(store: overview) }.deadlinerTheme().environment(\.colorScheme, .dark),
                    scheme: .dark, name: "desktop-dashboard-dark", width: 1450)
    }

    func testAIErrorReturnsToSwiftWithoutNetworkOrCrash() async throws {
        let bridge = AppleMonthlyInsightBridge()
        let config = AIConfig(apiKey: "", baseUrl: "https://invalid.invalid/v1", model: "test", platform: "macos",
                              timezone: "Asia/Shanghai", temperature: nil, nativeToolCalling: false, preferredLanguage: "zh-CN")
        var receivedError = false
        bridge.generate(config: config, month: "2026-10", metrics: "", titles: [], onSuccess: { _, _ in
            XCTFail("空密钥不应生成洞察")
        }, onError: { _ in MainActor.assumeIsolated { receivedError = true } })
        try await waitUntil { receivedError }
    }

    func testReviewPosterRendersPNG() throws {
        var review = OverviewStore.MonthReview()
        review.monthStart = "2026-10-01"
        review.totalTasks = 12
        review.completedTasks = 9
        review.completionRate = 75
        review.daily = (1...31).map { OverviewStore.DayCount(date: String(format: "2026-10-%02d", $0), completed: $0 % 3) }
        let insight = MonthlyInsight(month: "2026-10-01", summary: "这个月完成了多个阶段目标。", keywords: ["持续推进", "复盘"])
        let renderer = ImageRenderer(content: OverviewReviewPoster(review: review, insight: insight))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 620)
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1000)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots/review-export.png")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: output)
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

    private func capture<V: View>(_ view: V, scheme: ColorScheme, name: String, width: Double = 1300) async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 950)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        try await _Concurrency.Task.sleep(for: .milliseconds(800))
        if overview != nil {
            try await waitUntil { !self.overview.isLoading && !self.overview.monthLoading && !self.overview.intervalLoading && !self.overview.annualLoading }
            try await _Concurrency.Task.sleep(for: .milliseconds(100))
        }
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        let url = output.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT \(url.path)")
    }
}
