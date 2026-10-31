import XCTest
import Shared
@testable import Deadliner_for_macOS

/// 第四步验收：任务与分类的写入全部经过 Core，并进入变更日志。
@MainActor
final class TaskCommandsTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var commands: TaskCommands!
    private var categories: CategoryCommands!
    private var changes = 0

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-commands-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(
            databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
            deviceId: "macos-test-device"
        )
        changes = 0
        commands = TaskCommands(database: container.database) { [unowned self] in changes += 1 }
        categories = CategoryCommands(database: container.database) { [unowned self] in changes += 1 }
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testCreateAndEditTaskWithSubtasks() throws {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = TaskDraft(title: "  写报告  ", note: "备注", dueAt: due, isStarred: true, subtasks: [
            .init(id: "s1", content: "提纲", isCompleted: true),
            .init(id: "s2", content: "初稿", isCompleted: false),
            .init(id: "s3", content: "   ", isCompleted: false),
        ])
        let uid = try commands.save(draft)
        XCTAssertEqual(changes, 1)

        let created = try XCTUnwrap(container.database.tasks.find(uid: uid))
        XCTAssertEqual(created.title, "写报告")
        XCTAssertEqual(created.state, TaskState.active)
        XCTAssertEqual(created.dueAt, CoreClock.local(due))
        XCTAssertEqual(created.subtasks.filter { !$0.isDeleted }.map(\.content), ["提纲", "初稿"])

        draft = try XCTUnwrap(commands.draft(for: uid))
        draft.subtasks.swapAt(0, 1)
        draft.subtasks.removeLast()
        draft.subtasks.append(.init(id: "s4", content: "定稿", isCompleted: false))
        draft.categoryId = categories.list().first?.id
        try commands.save(draft)

        let edited = try XCTUnwrap(container.database.tasks.find(uid: uid))
        let live = edited.subtasks.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(live.map(\.content), ["初稿", "定稿"])
        XCTAssertFalse(edited.subtasks.contains { $0.uid == "s1" && !$0.isDeleted }, "移除的子任务不应再出现")
        let s1Changes = container.database.changeLog.pending().filter { $0.tableName == "task_subtask" && $0.recordId == "s1" }
        XCTAssertEqual(s1Changes.count, 2, "移除子任务应作为删除标记写入变更日志，便于同步到手机")
        XCTAssertEqual(edited.categoryUid, draft.categoryId)
        XCTAssertEqual(edited.createdAt, created.createdAt)
    }

    func testStateActionsFollowCoreStateMachine() throws {
        let uid = try commands.save(TaskDraft(title: "状态"))
        XCTAssertThrowsError(try commands.archive(uid)) { XCTAssertEqual($0 as? TaskCommandError, .invalidTransition) }

        try commands.toggleComplete(uid)
        XCTAssertEqual(container.database.tasks.find(uid: uid)?.state, TaskState.completed)
        try commands.toggleComplete(uid)
        XCTAssertEqual(container.database.tasks.find(uid: uid)?.state, TaskState.active)

        try commands.toggleGiveUp(uid)
        XCTAssertEqual(container.database.tasks.find(uid: uid)?.state, TaskState.abandoned)
        try commands.archive(uid)
        XCTAssertEqual(container.database.tasks.find(uid: uid)?.state, TaskState.abandonedArchived)
        try commands.unarchive(uid)
        XCTAssertEqual(container.database.tasks.find(uid: uid)?.state, TaskState.abandoned)

        XCTAssertTrue(TaskCommands.canApply(.markArchive, to: .completed))
        XCTAssertFalse(TaskCommands.canApply(.markArchive, to: .active))
        XCTAssertFalse(TaskCommands.canApply(.markGiveUp, to: .completed))
    }

    func testStarAndDelete() throws {
        let uid = try commands.save(TaskDraft(title: "删除我"))
        try commands.setStarred(uid, true)
        XCTAssertEqual(container.database.tasks.find(uid: uid)?.isStarred, true)

        let pending = container.database.changeLog.pending().count
        try commands.delete(uid)
        XCTAssertNil(container.database.tasks.list().first { $0.uid == uid && !$0.isDeleted })
        XCTAssertGreaterThan(container.database.changeLog.pending().count, pending, "删除应写入变更日志以便同步")
        XCTAssertThrowsError(try commands.setStarred(uid, false))
    }

    func testEmptyTitleIsRejected() {
        XCTAssertThrowsError(try commands.save(TaskDraft(title: "   "))) { XCTAssertEqual($0 as? TaskCommandError, .emptyTitle) }
        XCTAssertEqual(changes, 0)
    }

    func testCategoryLifecycle() throws {
        let before = categories.list()
        let uid = try categories.create(name: " 健身 ", iconKey: "fitness", colorHex: "#10B981")
        var created = try XCTUnwrap(categories.list().first { $0.id == uid })
        XCTAssertEqual(created.name, "健身")
        XCTAssertEqual(created.sortOrder, (before.map(\.sortOrder).max() ?? 0) + 10)

        try categories.update(id: uid, name: "运动", iconKey: "not-a-real-icon", colorHex: "red")
        created = try XCTUnwrap(categories.list().first { $0.id == uid })
        XCTAssertEqual(created.name, "运动")
        XCTAssertTrue(CategoryCommands.iconKeys.contains(created.iconKey), "Core 应把未知图标回退为支持的图标")
        XCTAssertNotNil(Color(hexString: created.colorHex), "Core 应把非法颜色回退为合法颜色")

        try categories.delete(id: uid)
        XCTAssertFalse(categories.list().contains { $0.id == uid })
        XCTAssertThrowsError(try categories.create(name: " ", iconKey: "folder", colorHex: "#3B82F6"))
    }
}

import SwiftUI
