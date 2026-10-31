import Foundation
import Shared

/// 编辑器里的任务草稿。新建时 `id` 为 nil。
struct TaskDraft: Equatable {
    struct Subtask: Identifiable, Equatable {
        let id: String
        var content: String
        var isCompleted: Bool
    }

    var id: String?
    var title = ""
    var note = ""
    var startAt: Date?
    var dueAt: Date?
    var categoryId: String?
    var isStarred = false
    var subtasks: [Subtask] = []

    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum TaskCommandError: LocalizedError, Equatable {
    case notFound
    case invalidTransition
    case focusTimerRunning
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .notFound: "任务不存在，可能已在其他设备上删除"
        case .invalidTransition: "当前状态下不能执行这个操作"
        case .focusTimerRunning: "这个任务正在专注计时，请先在手机上结束计时"
        case .emptyTitle: "标题不能为空"
        }
    }
}

/// 任务的写入命令。所有规则都由 Core 决定：
/// 状态转换走 `TaskRepository.applyAction`（内部是 TaskStateMachine），
/// 保存走 `create` / `update`（子任务随任务一起写入），删除走软删除。
@MainActor
final class TaskCommands {
    private let database: DeadlinerDatabase
    private let didChange: () -> Void

    init(database: DeadlinerDatabase, didChange: @escaping () -> Void) {
        self.database = database
        self.didChange = didChange
    }

    /// 读取一条任务为草稿，供编辑器使用。
    func draft(for uid: String) -> TaskDraft? {
        guard let task = database.tasks.find(uid: uid), !task.isDeleted else { return nil }
        return TaskDraft(
            id: task.uid,
            title: task.title,
            note: task.note,
            startAt: CoreDates.parseLocal(task.startAt),
            dueAt: CoreDates.parseLocal(task.dueAt),
            categoryId: task.categoryUid,
            isStarred: task.isStarred,
            subtasks: task.subtasks
                .filter { !$0.isDeleted }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { TaskDraft.Subtask(id: $0.uid, content: $0.content, isCompleted: $0.isCompleted) }
        )
    }

    /// 新建或保存任务，返回任务 uid。
    @discardableResult
    func save(_ draft: TaskDraft) throws -> String {
        guard draft.isValid else { throw TaskCommandError.emptyTitle }
        let now = CoreClock.now()
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let uid = draft.id {
            guard let existing = database.tasks.find(uid: uid), !existing.isDeleted else { throw TaskCommandError.notFound }
            let updated = existing.doCopy(
                uid: existing.uid, title: title, note: draft.note,
                startAt: CoreClock.local(draft.startAt), dueAt: CoreClock.local(draft.dueAt),
                state: existing.state, completedAt: existing.completedAt, categoryUid: draft.categoryId,
                isStarred: draft.isStarred, calendarEventId: existing.calendarEventId,
                createdAt: existing.createdAt, updatedAt: now, isDeleted: false,
                subtasks: mergedSubtasks(existing: existing.subtasks, draft: draft.subtasks, taskUid: uid, now: now)
            )
            try check(database.tasks.update(task: updated).outcome)
            didChange()
            return uid
        }

        let uid = PlatformIdentity.shared.doNewId()
        let task = Task_(
            uid: uid, title: title, note: draft.note,
            startAt: CoreClock.local(draft.startAt), dueAt: CoreClock.local(draft.dueAt),
            state: TaskState.active, completedAt: nil, categoryUid: draft.categoryId,
            isStarred: draft.isStarred, calendarEventId: nil, createdAt: now, updatedAt: now, isDeleted: false,
            subtasks: mergedSubtasks(existing: [], draft: draft.subtasks, taskUid: uid, now: now)
        )
        database.tasks.create(task: task)
        didChange()
        return uid
    }

    /// 勾选完成 / 取消完成（Core 中 MARK_COMPLETE 在两者之间切换）。
    func toggleComplete(_ uid: String) throws { try apply(TaskAction.markComplete, to: uid) }

    /// 放弃 / 取消放弃（Core 中 MARK_GIVE_UP 在两者之间切换）。
    func toggleGiveUp(_ uid: String) throws { try apply(TaskAction.markGiveUp, to: uid) }

    func archive(_ uid: String) throws { try apply(TaskAction.markArchive, to: uid) }

    func unarchive(_ uid: String) throws { try apply(TaskAction.unarchive, to: uid) }

    func setStarred(_ uid: String, _ starred: Bool) throws {
        guard var draft = draft(for: uid) else { throw TaskCommandError.notFound }
        draft.isStarred = starred
        try save(draft)
    }

    func delete(_ uid: String) throws {
        try check(database.tasks.delete(uid: uid, updatedAt: CoreClock.now()).outcome)
        didChange()
    }

    /// Core 的状态机是否允许这个操作（用于决定菜单项是否可用）。
    static func canApply(_ action: TaskAction, to state: TaskItem.State) -> Bool {
        guard let coreState = TaskState.entries.first(where: { $0.name == state.rawValue }) else { return false }
        return TaskStateMachine.shared.apply(current: coreState, action: action) != nil
            && !TaskStateMachine.shared.isNoOp(state: coreState, action: action)
    }

    private func apply(_ action: TaskAction, to uid: String) throws {
        try check(database.tasks.applyAction(uid: uid, action: action, occurredAt: CoreClock.now()).outcome)
        didChange()
    }

    private func check(_ outcome: TaskActionOutcome) throws {
        switch outcome.name {
        case "APPLIED", "NO_OP": return
        case "NOT_FOUND": throw TaskCommandError.notFound
        case "TIMER_REQUIRES_RESOLUTION": throw TaskCommandError.focusTimerRunning
        default: throw TaskCommandError.invalidTransition
        }
    }

    /// 草稿中的子任务与已有子任务合并：保留原创建时间，顺序即 sortOrder，草稿中没有的标记为删除。
    private func mergedSubtasks(existing: [TaskSubtask], draft: [TaskDraft.Subtask], taskUid: String, now: String) -> [TaskSubtask] {
        let byId = Dictionary(existing.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [TaskSubtask] = []
        for (index, item) in draft.enumerated() {
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            let sortOrder = Int32(index)
            if let old = byId[item.id], !old.isDeleted {
                let changed = old.content != content || old.isCompleted != item.isCompleted || old.sortOrder != sortOrder
                result.append(TaskSubtask(
                    uid: old.uid, taskUid: taskUid, content: content, isCompleted: item.isCompleted, sortOrder: sortOrder,
                    createdAt: old.createdAt, updatedAt: changed ? now : old.updatedAt, isDeleted: false
                ))
            } else {
                result.append(TaskSubtask(
                    uid: item.id, taskUid: taskUid, content: content, isCompleted: item.isCompleted, sortOrder: sortOrder,
                    createdAt: now, updatedAt: now, isDeleted: false
                ))
            }
        }
        let kept = Set(result.map(\.uid))
        for old in existing where !old.isDeleted && !kept.contains(old.uid) {
            result.append(TaskSubtask(
                uid: old.uid, taskUid: taskUid, content: old.content, isCompleted: old.isCompleted, sortOrder: old.sortOrder,
                createdAt: old.createdAt, updatedAt: now, isDeleted: true
            ))
        }
        return result
    }
}
