import Foundation
import Shared

enum CategoryCommandError: LocalizedError {
    case emptyName
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyName: "分类名称不能为空"
        case .notFound: "分类不存在，可能已在其他设备上删除"
        }
    }
}

/// 分类的写入命令。名称、图标、颜色的校验与回退由 Core 的 `CategoryMutation` 负责，
/// 排序值的计算与鸿蒙端一致（现有最大值 + 10）。
@MainActor
final class CategoryCommands {
    /// 可选图标，与 Core `CategoryMutation` 支持的语义 ID 一致。
    nonisolated static let iconKeys = [
        "folder", "inbox_tray", "briefcase", "office_building", "book", "education", "edit", "home",
        "shopping", "dining", "coffee", "health", "medical", "running", "fitness", "payment_card",
        "cash", "analytics", "group", "family", "creativity", "camera", "music", "reading", "inspiration",
        "calendar", "time", "flag", "idea", "travel", "flight", "gaming", "tools", "construction", "nature", "tag",
    ]

    /// 可选颜色：Core 预设分类使用的颜色。
    nonisolated static let colors = ["#3B82F6", "#8B5CF6", "#10B981", "#EF4444", "#F59E0B", "#EC4899", "#06B6D4", "#6366F1"]

    private let database: DeadlinerDatabase
    private let didChange: () -> Void

    init(database: DeadlinerDatabase, didChange: @escaping () -> Void) {
        self.database = database
        self.didChange = didChange
    }

    func list() -> [CategoryItem] {
        database.categories.list().filter { !$0.isDeleted }.map(CategoryItem.init(core:)).sorted { $0.sortOrder < $1.sortOrder }
    }

    @discardableResult
    func create(name: String, iconKey: String, colorHex: String) throws -> String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CategoryCommandError.emptyName }
        let existing = database.categories.list().filter { !$0.isDeleted }
        let nextSortOrder = (existing.map { Int($0.sortOrder) }.max() ?? 0) + 10
        let request = CategoryMutationRequest(uid: nil, name: name, iconKey: iconKey, colorHex: colorHex)
        let category = CategoryMutation.shared.create(
            request: request, uid: PlatformIdentity.shared.doNewId(), sortOrder: Int32(nextSortOrder), now: CoreClock.now()
        )
        database.categories.create(category: category)
        didChange()
        return category.uid
    }

    func update(id: String, name: String, iconKey: String, colorHex: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CategoryCommandError.emptyName }
        guard let existing = database.categories.find(uid: id), !existing.isDeleted else { throw CategoryCommandError.notFound }
        let request = CategoryMutationRequest(uid: id, name: name, iconKey: iconKey, colorHex: colorHex)
        database.categories.update(category: CategoryMutation.shared.update(existing: existing, request: request, now: CoreClock.now()))
        didChange()
    }

    func delete(id: String) throws {
        guard database.categories.find(uid: id) != nil else { throw CategoryCommandError.notFound }
        database.categories.softDelete(uid: id, updatedAt: CoreClock.now())
        didChange()
    }

    /// 一个分类里的内容（与 iOS 的分类详情相同）：任务（包括已完成和归档的）与习惯。`id` 为 nil 表示未分类。
    struct Contents: Equatable {
        struct Habit: Identifiable, Equatable {
            let id: String
            let name: String
            let colorHex: String?
            let isArchived: Bool
        }
        var tasks: [TaskItem] = []
        var habits: [Habit] = []
        var isEmpty: Bool { tasks.isEmpty && habits.isEmpty }
    }

    func contents(of id: String?) -> Contents {
        let known = Set(list().map(\.id))
        // 分类已删除的任务和习惯按「未分类」显示（与任务页的筛选一致）。
        func matches(_ uid: String?) -> Bool {
            guard let id else { return uid == nil || !known.contains(uid!) }
            return uid == id
        }
        let tasks = database.tasks.list()
            .filter { !$0.isDeleted && matches($0.categoryUid) }
            .map(TaskItem.init(core:))
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let habits = database.habits.list()
            .filter { !$0.isDeleted && matches($0.categoryUid) }
            .map { Contents.Habit(id: $0.uid, name: $0.name, colorHex: $0.color.map { HabitItem.hex(fromArgb: $0.intValue) },
                                  isArchived: $0.status.name == "ARCHIVED") }
            .sorted { !$0.isArchived && $1.isArchived }
        return Contents(tasks: tasks, habits: habits)
    }

    /// 已删除的预设分类重新加回来（Core `restorePresets`）。
    func restorePresets() {
        _ = database.categories.restorePresets()
        didChange()
    }
}
