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

        for section in OverviewSection.allCases {
            for scheme in [ColorScheme.light, .dark] {
                try capture(
                    OverviewContent(store: overview, section: section, layout: .double)
                        .deadlinerTheme()
                        .environment(\.colorScheme, scheme),
                    scheme: scheme,
                    name: "overview-\(section.rawValue)-\(scheme == .dark ? "dark" : "light")"
                )
            }
        }
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
        XCTAssertEqual(OverviewMetricsCard.percent(0.666), "67%")
        XCTAssertEqual(OverviewMetricsCard.pointDelta(0.1), "+10%")
        XCTAssertNil(OverviewMetricsCard.pointDelta(0.001))
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
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 900)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.backgroundColor = scheme == .dark ? .black : .white
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
