import XCTest
import Shared
@testable import DeadlinerTestHost

/// 对齐手机的基础功能：延期、分类筛选、显示设置、归档搜索、后台同步间隔。
@MainActor
final class TaskListFeatureTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var commands: TaskCommands!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-feature-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
                                     deviceId: "macos-test-device")
        commands = TaskCommands(database: container.database) {}
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func add(_ title: String, due: Date? = nil, category: String? = nil) throws -> String {
        var draft = TaskDraft()
        draft.title = title
        draft.dueAt = due
        draft.categoryId = category
        return try commands.save(draft)
    }

    func testPostponeThroughCore() throws {
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        let uid = try add("示例延期", due: due)
        try commands.postpone(uid, amount: 1, inHours: false)
        XCTAssertEqual(commands.draft(for: uid)?.dueAt?.timeIntervalSince(due) ?? 0, 86400, accuracy: 3700)
        try commands.postpone(uid, amount: 3, inHours: true)
        XCTAssertEqual(commands.draft(for: uid)?.dueAt?.timeIntervalSince(due) ?? 0, 86400 + 3 * 3600, accuracy: 3700)

        let noDue = try add("示例无截止")
        XCTAssertThrowsError(try commands.postpone(noDue, amount: 1, inHours: false)) {
            XCTAssertEqual($0 as? TaskCommandError, .noDeadline)
        }
        // Core 只允许 1～7 天。
        XCTAssertThrowsError(try commands.postpone(uid, amount: 8, inHours: false))
    }

    func testCategoryFilter() async throws {
        let category = try CategoryCommands(database: container.database) {}.create(name: "示例分类", iconKey: "folder", colorHex: "#4A90E2")
        _ = try add("示例甲", category: category)
        _ = try add("示例乙")
        let store = TaskListStore(database: container.database)
        store.start()
        defer { store.stop() }
        let deadline = Date().addingTimeInterval(3)
        while store.tasks.count < 2 && Date() < deadline { try await _Concurrency.Task.sleep(nanoseconds: 20_000_000) }

        XCTAssertEqual(store.visibleTasks.count, 2)
        store.categoryFilter = category
        XCTAssertEqual(store.visibleTasks.map(\.title), ["示例甲"])
        store.categoryFilter = TaskListStore.uncategorized
        XCTAssertEqual(store.visibleTasks.map(\.title), ["示例乙"])
        store.categoryFilter = nil
        store.searchText = "乙"
        XCTAssertEqual(store.visibleTasks.map(\.title), ["示例乙"])
    }

    func testDisplaySettings() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = TaskItem(id: "1", title: "示例", note: "", startAt: nil, dueAt: now.addingTimeInterval(86400 * 2 + 3 * 3600),
                            state: .active, isStarred: false, categoryId: nil, subtaskDone: 0, subtaskTotal: 0,
                            createdAt: now.addingTimeInterval(-86400 * 2), updatedAt: nil)
        XCTAssertEqual(TaskStatus.remainingText(task, now: now, detailed: true), "2天 3小时")
        XCTAssertEqual(TaskStatus.remainingText(task, now: now, detailed: false), "2天")
        let remaining = TaskStatus.displayedProgress(task, now: now, forward: false)
        XCTAssertEqual(TaskStatus.displayedProgress(task, now: now, forward: true), 1 - remaining, accuracy: 0.0001)
    }

    func testArchiveSearch() throws {
        let uid = try add("示例归档报告")
        try commands.toggleComplete(uid)
        try commands.archive(uid)
        _ = try add("示例进行中")
        let archive = ArchiveStore(database: container.database)
        archive.refresh()
        XCTAssertEqual(archive.taskMatchCount("报告"), 1)
        XCTAssertEqual(archive.taskMatchCount("进行中"), 0)
        XCTAssertEqual(archive.taskMatchCount(" "), 0)
        archive.searchText = "报告"
        XCTAssertEqual(archive.visibleTasks.count, 1)
    }

    func testBackgroundIntervalPersists() {
        let defaults = UserDefaults(suiteName: "interval-tests-\(UUID().uuidString)")!
        XCTAssertEqual(SyncSettings.load(from: defaults).backgroundInterval, 15)
        var settings = SyncSettings.load(from: defaults)
        settings.backgroundInterval = 60
        settings.save(to: defaults)
        XCTAssertEqual(SyncSettings.load(from: defaults).backgroundInterval, 60)
    }
}
