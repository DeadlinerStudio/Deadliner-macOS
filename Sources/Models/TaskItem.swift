import Foundation
import Shared

/// 界面使用的任务快照。视图只依赖这些 Swift 值类型，不直接接触 Core 的 Kotlin 对象，
/// 这样订阅层以后换实现时界面不用改，预览和截图测试也不需要数据库。
struct TaskItem: Identifiable, Equatable {
    enum State: String {
        case active = "ACTIVE"
        case completed = "COMPLETED"
        case archived = "ARCHIVED"
        case abandoned = "ABANDONED"
        case abandonedArchived = "ABANDONED_ARCHIVED"
    }

    let id: String
    var title: String
    var note: String
    var startAt: Date?
    var dueAt: Date?
    var state: State
    var isStarred: Bool
    var categoryId: String?
    var subtaskDone: Int
    var subtaskTotal: Int
    var createdAt: Date?
    var updatedAt: Date?

    /// 已归档的任务按「已完成」显示，放弃后归档的按「已放弃」显示。
    var isCompleted: Bool { state == .completed || state == .archived }
    var isAbandoned: Bool { state == .abandoned || state == .abandonedArchived }
}

extension TaskItem {
    init(core task: Task_) {
        let subtasks = task.subtasks.filter { !$0.isDeleted }
        self.init(
            id: task.uid,
            title: task.title,
            note: task.note,
            startAt: CoreDates.parseLocal(task.startAt),
            dueAt: CoreDates.parseLocal(task.dueAt),
            state: State(rawValue: task.state.name) ?? .active,
            isStarred: task.isStarred,
            categoryId: task.categoryUid,
            subtaskDone: subtasks.filter(\.isCompleted).count,
            subtaskTotal: subtasks.count,
            createdAt: CoreDates.parseInstant(task.createdAt),
            updatedAt: CoreDates.parseInstant(task.updatedAt)
        )
    }
}

/// 界面使用的分类快照。
struct CategoryItem: Identifiable, Equatable {
    let id: String
    var name: String
    var iconKey: String
    var colorHex: String
    var sortOrder: Int

    init(id: String, name: String, iconKey: String, colorHex: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.iconKey = iconKey
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }

    init(core category: Category_) {
        self.init(
            id: category.uid,
            name: category.name,
            iconKey: category.iconKey,
            colorHex: category.colorHex,
            sortOrder: Int(category.sortOrder)
        )
    }
}
