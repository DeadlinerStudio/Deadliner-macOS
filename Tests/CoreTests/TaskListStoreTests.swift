import XCTest
import Shared
@testable import DeadlinerTestHost

/// 第三步验收：订阅层能收到 Core 的状态，主列表可见性与排序遵循 Core 规则。
@MainActor
final class TaskListStoreTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var store: TaskListStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(
            databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
            deviceId: "macos-test-device"
        )
    }

    override func tearDown() async throws {
        store?.stop()
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testShowsOnlyMainListTasksInCoreOrder() async throws {
        let category = try XCTUnwrap(container.database.categories.list().first, "Core 应自带预设分类")
        insert("普通", state: .active, due: "2026-12-01T09:00:00")
        insert("更早截止", state: .active, due: "2026-11-20T09:00:00", categoryUid: category.uid)
        insert("标星", state: .active, due: "2026-12-30T09:00:00", starred: true)
        insert("已完成", state: .completed, due: "2026-11-01T09:00:00")
        insert("已归档", state: .archived, due: "2026-11-01T09:00:00")
        insert("放弃后归档", state: .abandonedArchived, due: nil)

        store = TaskListStore(database: container.database)
        store.start()
        try await waitUntil { !self.store.isLoading && self.store.tasks.count == 4 }

        XCTAssertEqual(store.visibleTasks.map(\.title), ["标星", "更早截止", "普通", "已完成"])
        let early = try XCTUnwrap(store.visibleTasks.first { $0.title == "更早截止" })
        XCTAssertEqual(early.categoryId.flatMap { store.categories[$0] }?.name, category.name)

        store.searchText = "早"
        XCTAssertEqual(store.visibleTasks.map(\.title), ["更早截止"])
    }

    func testRefreshPicksUpWritesFromElsewhere() async throws {
        store = TaskListStore(database: container.database)
        store.start()
        try await waitUntil { !self.store.isLoading }
        XCTAssertTrue(store.tasks.isEmpty)

        insert("同步进来的任务", state: .active, due: nil)
        store.refresh()
        try await waitUntil { self.store.tasks.count == 1 }
        XCTAssertEqual(store.tasks.first?.title, "同步进来的任务")
    }

    // MARK: - Helpers

    private func insert(_ title: String, state: TaskItem.State, due: String?, starred: Bool = false, categoryUid: String? = nil) {
        let now = ISO8601DateFormatter().string(from: Date())
        let coreState = TaskState.entries.first { $0.name == state.rawValue }!
        container.database.tasks.create(task: Task_(
            uid: UUID().uuidString.lowercased(), title: title, note: "", startAt: nil, dueAt: due,
            state: coreState, completedAt: nil, categoryUid: categoryUid, isStarred: starred,
            calendarEventId: nil, createdAt: now, updatedAt: now, isDeleted: false, subtasks: []
        ))
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("等待 Core 状态超时") }
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
