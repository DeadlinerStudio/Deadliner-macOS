import XCTest
@testable import DeadlinerTestHost

/// 月度复盘随月份切换：已保存的洞察直接显示，其他月份不会自动发起 AI 请求，进行中的月份暂不生成。
@MainActor
final class OverviewMonthTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("insight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func review(_ month: String) -> OverviewStore.MonthReview {
        var review = OverviewStore.MonthReview()
        review.monthStart = month
        return review
    }

    func testBrowsingAMonthWithoutAnInsightDoesNotStartARequest() {
        let store = MonthlyInsightStore(directory: directory)
        store.resolve(review: review("2026-03-01"), generate: false)
        XCTAssertTrue(store.awaitingRequest)
        XCTAssertFalse(store.loading)
        XCTAssertNil(store.error)
        XCTAssertNil(store.result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("2026-03-01.json").path),
                       "没有发起生成，不应留下「已尝试」记录")
    }

    func testSavedInsightIsShownForAnyMonth() throws {
        struct Record: Codable { var attempted: Bool; var result: MonthlyInsight? }
        let saved = MonthlyInsight(month: "2026-02-01", summary: "示例总结", keywords: ["示例"])
        try JSONEncoder().encode(Record(attempted: true, result: saved)).write(to: directory.appendingPathComponent("2026-02-01.json"))
        let store = MonthlyInsightStore(directory: directory)
        store.resolve(review: review("2026-02-01"), generate: false)
        XCTAssertEqual(store.result, saved)
        XCTAssertFalse(store.awaitingRequest)
    }

    func testMonthInProgressIsNotAnalysed() {
        let store = MonthlyInsightStore(directory: directory)
        store.resolve(review: review(OverviewPeriod.key(OverviewPeriod.month())), retry: true)
        XCTAssertTrue(store.monthInProgress)
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.awaitingRequest)
    }

    func testFocusTileSecondLine() {
        XCTAssertEqual(FocusTexts.tileAverage(.init(totalSeconds: 7200, sessionCount: 4), days: 2),
                       String(localized: "日均 \(FocusTexts.duration(3600))"))
        XCTAssertEqual(FocusTexts.tileAverage(.init(totalSeconds: 5400, sessionCount: 2), days: nil),
                       String(localized: "平均每次 \(FocusTexts.duration(2700))"))
        XCTAssertEqual(FocusTexts.tileAverage(.init(totalSeconds: 0, sessionCount: 0), days: nil), String(localized: "平均每次 —"))
    }

    func testMonthlyHoverLines() {
        let month = OverviewStore.MonthCount(monthStart: "2026-10-01", total: 12, completed: 9, overdueCompleted: 2)
        XCTAssertEqual(OverviewMonthlyCard.hoverLines(month, timings: [.ahead: 1, .early: 3]).count, 5)
        let day = OverviewStore.DayCount(date: "2026-10-05", completed: 3, overdue: 0)
        XCTAssertEqual(OverviewHeatmapCard.hoverLines(day, focusSeconds: 0).lines.count, 1)
        XCTAssertEqual(OverviewHeatmapCard.hoverLines(day, focusSeconds: 1800).lines.count, 2)
    }
}
