import Foundation
import Shared

/// 执行 Lifi 请求的工具（与 iOS 的 ToolCallExecutor 相同的结果格式，回传给模型）。
/// - 读取任务 / 习惯：只读，返回摘要；
/// - 创建任务 / 习惯：只校验并生成草案（`pendingUserConfirmation`），真正写入由用户在对话中确认；
/// - 修改截止时间：直接写入（执行前已经征得用户同意）。
@MainActor
struct LifiToolExecutor {
    let database: DeadlinerDatabase
    let didChange: () -> Void

    struct Result: Equatable {
        let tool: String
        let json: String
        let message: String
    }

    static func name(of call: ToolCall) -> String {
        switch call {
        case is ToolCall.ReadTasks: "read_tasks"
        case is ToolCall.CreateTask: "create_task"
        case is ToolCall.UpdateDeadline: "update_deadline"
        case is ToolCall.ReadHabits: "read_habits"
        case is ToolCall.CreateHabit: "create_habit"
        default: "unknown"
        }
    }

    /// 只读的工具（需要「允许读取」）。
    static func isRead(_ call: ToolCall) -> Bool { call is ToolCall.ReadTasks || call is ToolCall.ReadHabits }

    /// 会直接修改数据的工具（需要用户确认）。
    static func isWrite(_ call: ToolCall) -> Bool { call is ToolCall.UpdateDeadline }

    func execute(_ call: ToolCall, now: Date = Date()) -> Result {
        switch call {
        case let tool as ToolCall.ReadTasks:
            return readTasks(days: tool.timeRangeDays.map { Int(truncating: $0) }, status: tool.status, keywords: tool.keywords,
                             limit: Int(tool.limit), sort: tool.sort, now: now)
        case let tool as ToolCall.CreateTask:
            let name = tool.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return failure("create_task", "INVALID_ARGS", String(localized: "create_task 需要非空任务名称")) }
            let due = (tool.dueTime ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !due.isEmpty && LifiDrafts.parseDue(due) == nil {
                return encode("create_task", CreateTaskPayload(ok: false, task: nil, createdTasks: [],
                                                               items: [.init(ok: false, item: nil, message: String(localized: "dueTime 格式无效，需为 yyyy-MM-dd HH:mm"))],
                                                               summary: .init(total: 1, success: 0, failed: 1), pendingUserConfirmation: false),
                              message: String(localized: "任务草案无效"))
            }
            let item = TaskItemPayload(id: nil, name: name, due: due, note: tool.note ?? "")
            return encode("create_task", CreateTaskPayload(ok: true, task: item, createdTasks: [item], items: [.init(ok: true, item: item, message: nil)],
                                                           summary: .init(total: 1, success: 1, failed: 0), pendingUserConfirmation: true),
                          message: String(localized: "已生成任务草案，请确认是否创建"))
        case let tool as ToolCall.UpdateDeadline:
            return updateDeadline(uid: tool.taskId, newDue: tool.newDueTime)
        case let tool as ToolCall.ReadHabits:
            return readHabits(keywords: tool.keywords)
        case let tool as ToolCall.CreateHabit:
            let name = tool.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return failure("create_habit", "INVALID_ARGS", String(localized: "create_habit 需要非空习惯名称")) }
            let item = HabitItemPayload(id: nil, name: name, period: tool.period, timesPerPeriod: max(1, Int(tool.timesPerPeriod)),
                                        goalType: tool.goalType, totalTarget: tool.totalTarget.map { Int(truncating: $0) })
            return encode("create_habit", CreateHabitPayload(ok: true, habit: item, createdHabits: [item], items: [.init(ok: true, item: item, message: nil)],
                                                             summary: .init(total: 1, success: 1, failed: 0), pendingUserConfirmation: true),
                          message: String(localized: "已生成习惯草案，请确认是否创建"))
        default:
            return failure("unknown", "UNSUPPORTED_TOOL", String(localized: "Lifi 请求了未支持的工具"))
        }
    }

    static func denied(_ call: ToolCall) -> Result {
        let tool = name(of: call)
        let json = (try? String(data: JSONEncoder().encode(Failure(ok: false, errorCode: "USER_DENIED", message: String(localized: "用户拒绝了这次操作"))), encoding: .utf8))
            ?? #"{"ok":false,"errorCode":"USER_DENIED"}"#
        return Result(tool: tool, json: json, message: String(localized: "已拒绝"))
    }

    // MARK: - 读取任务（与 iOS 相同的筛选：默认前后 7 天、未完成、按截止时间升序、最多 20 条）

    private func readTasks(days: Int?, status: String?, keywords: [String], limit: Int, sort: String?, now: Date) -> Result {
        let all = database.tasks.list().filter { !$0.isDeleted }.map(TaskItem.init(core:))
            .filter { $0.state != .archived && $0.state != .abandonedArchived }
        let range = TimeInterval(days ?? 7) * 86400
        let words = keywords.map { $0.lowercased() }.filter { !$0.isEmpty }
        let want = (status ?? "OPEN").uppercased()
        func statusMatches(_ task: TaskItem) -> Bool {
            want == "OPEN" ? task.state == .active : want == "DONE" ? task.isCompleted : true
        }
        func keywordMatches(_ task: TaskItem) -> Bool {
            words.isEmpty || words.allSatisfy { "\(task.title) \(task.note)".lowercased().contains($0) }
        }
        var picked = all.filter { task in
            guard statusMatches(task), keywordMatches(task) else { return false }
            if let due = task.dueAt { return due >= now - range && due <= now + range }
            if let updated = task.updatedAt ?? task.createdAt { return updated >= now - range }
            return !words.isEmpty
        }
        if picked.isEmpty && words.isEmpty { picked = all.filter(statusMatches) }
        if (sort ?? "").uppercased() == "UPDATED_DESC" {
            picked.sort { ($0.updatedAt ?? $0.dueAt ?? .distantPast) > ($1.updatedAt ?? $1.dueAt ?? .distantPast) }
        } else {
            picked.sort { ($0.dueAt ?? $0.updatedAt ?? .distantFuture) < ($1.dueAt ?? $1.updatedAt ?? .distantFuture) }
        }
        picked = Array(picked.prefix(max(1, limit)))
        let overdue = picked.filter { ($0.dueAt ?? .distantFuture) < now }.count
        let soon = picked.filter { guard let due = $0.dueAt else { return false }; return due >= now && due <= now + 86400 }.count
        let payload = ReadTasksPayload(
            tasks: picked.map { TaskDigest(id: $0.id, name: $0.title, due: $0.dueAt.map { TaskShareLink.localString($0) } ?? "",
                                           status: $0.isCompleted ? "DONE" : "OPEN", notePreview: String($0.note.prefix(40))) },
            summary: .init(count: picked.count, overdue: overdue, dueSoon24h: soon))
        return encode("read_tasks", payload, message: String(localized: "已读取任务 \(picked.count) 条（逾期 \(overdue)，24 小时内 \(soon)）"))
    }

    private func readHabits(keywords: [String]) -> Result {
        let words = keywords.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        let habits = database.habits.list().filter { habit in
            !habit.isDeleted && (words.isEmpty || words.allSatisfy { "\(habit.name) \(habit.description_)".lowercased().contains($0) })
        }
        let payload = ReadHabitsPayload(
            habits: habits.map { HabitDigest(id: $0.uid, name: $0.name, period: $0.goal.window.name, timesPerPeriod: Int($0.goal.targetCount),
                                             goalType: $0.goal.window.name == "LIFETIME" ? "TOTAL" : "PER_PERIOD",
                                             totalTarget: $0.goal.window.name == "LIFETIME" ? Int($0.goal.targetCount) : nil,
                                             status: $0.status.name) },
            summary: .init(count: habits.count, active: habits.filter { $0.status.name == "ACTIVE" }.count,
                           archived: habits.filter { $0.status.name == "ARCHIVED" }.count))
        return encode("read_habits", payload, message: String(localized: "已读取习惯 \(habits.count) 条"))
    }

    private func updateDeadline(uid: String, newDue: String) -> Result {
        guard !uid.trimmingCharacters(in: .whitespaces).isEmpty else { return failure("update_deadline", "INVALID_ARGS", String(localized: "update_deadline 需要任务 ID")) }
        guard let due = LifiDrafts.parseDue(newDue) else { return failure("update_deadline", "INVALID_DATE", String(localized: "newDueTime 无法解析")) }
        guard let task = database.tasks.find(uid: uid), !task.isDeleted else { return failure("update_deadline", "TASK_NOT_FOUND", String(localized: "未找到任务 \(uid)")) }
        let updated = task.doCopy(uid: task.uid, title: task.title, note: task.note, startAt: task.startAt, dueAt: CoreClock.local(due),
                                  state: task.state, completedAt: task.completedAt, categoryUid: task.categoryUid, isStarred: task.isStarred,
                                  calendarEventId: task.calendarEventId, createdAt: task.createdAt, updatedAt: CoreClock.now(),
                                  isDeleted: false, subtasks: task.subtasks)
        let outcome = database.tasks.update(task: updated).outcome.name
        guard outcome == "APPLIED" || outcome == "NO_OP" else { return failure("update_deadline", outcome, String(localized: "无法修改这个任务的截止时间")) }
        didChange()
        let item = TaskItemPayload(id: task.uid, name: task.title, due: TaskShareLink.localString(due), note: task.note)
        return encode("update_deadline", UpdateDeadlinePayload(ok: true, task: item), message: String(localized: "已更新截止时间：\(task.title)"))
    }

    private func failure(_ tool: String, _ code: String, _ message: String) -> Result {
        encode(tool, Failure(ok: false, errorCode: code, message: message), message: String(localized: "工具执行失败：\(message)"))
    }

    private func encode<T: Encodable>(_ tool: String, _ payload: T, message: String) -> Result {
        let json = (try? String(data: JSONEncoder().encode(payload), encoding: .utf8)) ?? #"{"ok":false}"#
        return Result(tool: tool, json: json, message: message)
    }

    // MARK: - 结果格式（与 iOS 相同）

    private struct Failure: Codable { let ok: Bool; let errorCode: String; let message: String }
    struct TaskItemPayload: Codable { let id: String?; let name: String; let due: String; let note: String }
    private struct Summary: Codable { let total: Int; let success: Int; let failed: Int }
    private struct TaskResultItem: Codable { let ok: Bool; let item: TaskItemPayload?; let message: String? }
    private struct CreateTaskPayload: Codable {
        let ok: Bool; let task: TaskItemPayload?; let createdTasks: [TaskItemPayload]; let items: [TaskResultItem]
        let summary: Summary; let pendingUserConfirmation: Bool
    }
    private struct UpdateDeadlinePayload: Codable { let ok: Bool; let task: TaskItemPayload }
    private struct TaskDigest: Codable { let id: String; let name: String; let due: String; let status: String; let notePreview: String }
    private struct TaskSummary: Codable { let count: Int; let overdue: Int; let dueSoon24h: Int }
    private struct ReadTasksPayload: Codable { let tasks: [TaskDigest]; let summary: TaskSummary }
    struct HabitItemPayload: Codable {
        let id: String?; let name: String; let period: String; let timesPerPeriod: Int; let goalType: String; let totalTarget: Int?
    }
    private struct HabitResultItem: Codable { let ok: Bool; let item: HabitItemPayload?; let message: String? }
    private struct CreateHabitPayload: Codable {
        let ok: Bool; let habit: HabitItemPayload?; let createdHabits: [HabitItemPayload]; let items: [HabitResultItem]
        let summary: Summary; let pendingUserConfirmation: Bool
    }
    private struct HabitDigest: Codable {
        let id: String; let name: String; let period: String; let timesPerPeriod: Int; let goalType: String; let totalTarget: Int?; let status: String
    }
    private struct HabitSummary: Codable { let count: Int; let active: Int; let archived: Int }
    private struct ReadHabitsPayload: Codable { let habits: [HabitDigest]; let summary: HabitSummary }
}
