import XCTest
import Shared
@testable import Deadliner_for_macOS

/// 第二步验收：建库 → 写一条任务 → 读出来，并确认写入进入了变更日志（同步的基础）。
@MainActor
final class CoreSmokeTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-mac-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(
            databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
            deviceId: "macos-test-device"
        )
    }

    override func tearDown() async throws {
        container?.close()
        container = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testCreateAndReadTask() throws {
        let now = Self.timestamp()
        let uid = UUID().uuidString.lowercased()
        let task = Task_(
            uid: uid, title: "冒烟测试任务", note: "备注", startAt: nil, dueAt: nil,
            state: TaskState.active, completedAt: nil, categoryUid: nil, isStarred: true,
            calendarEventId: nil, createdAt: now, updatedAt: now, isDeleted: false, subtasks: []
        )
        let tasks = container.database.tasks
        let pendingBefore = container.database.changeLog.pending().count

        tasks.create(task: task)

        let loaded = try XCTUnwrap(tasks.find(uid: uid))
        XCTAssertEqual(loaded.title, "冒烟测试任务")
        XCTAssertEqual(loaded.note, "备注")
        XCTAssertTrue(loaded.isStarred)
        XCTAssertEqual(loaded.state, TaskState.active)
        XCTAssertTrue(tasks.list().contains { $0.uid == uid })
        XCTAssertGreaterThan(container.database.changeLog.pending().count, pendingBefore)
    }

    func testDataSurvivesReopen() throws {
        let now = Self.timestamp()
        let uid = UUID().uuidString.lowercased()
        container.database.tasks.create(task: Task_(
            uid: uid, title: "重新打开", note: "", startAt: nil, dueAt: nil,
            state: TaskState.active, completedAt: nil, categoryUid: nil, isStarred: false,
            calendarEventId: nil, createdAt: now, updatedAt: now, isDeleted: false, subtasks: []
        ))
        let url = container.databaseURL
        container.close()

        container = MacCoreContainer(databaseURL: url, deviceId: "macos-test-device")
        XCTAssertEqual(container.database.tasks.find(uid: uid)?.title, "重新打开")
    }

    func testCoreVersionIsEmbedded() {
        XCTAssertTrue(MacCoreContainer.coreVersion.hasPrefix("DeadlinerCore-"))
    }

    /// 与 Core 的 `Clock.System.now().toString()` 相同的 ISO-8601 UTC 格式。
    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
