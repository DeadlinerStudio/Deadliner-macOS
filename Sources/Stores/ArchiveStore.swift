import Foundation
import Observation
import Shared

/// 归档页：已归档 / 放弃后归档的任务（Core `TaskStateMachine.isVisibleInArchive`），以及已归档的习惯。
@MainActor
@Observable
final class ArchiveStore {
    struct ArchivedHabit: Identifiable, Equatable {
        let id: String
        var name: String
        var colorHex: String?
        var categoryId: String?
    }

    private(set) var tasks: [TaskItem] = []
    private(set) var habits: [ArchivedHabit] = []
    private(set) var categories: [String: CategoryItem] = [:]
    var searchText = ""

    /// 按搜索词过滤后的归档任务与习惯。
    var visibleTasks: [TaskItem] { tasks.filter { Self.matches($0, searchText) } }
    var visibleHabits: [ArchivedHabit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? habits : habits.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// 任务页搜索时，归档中匹配的任务数。
    func taskMatchCount(_ query: String) -> Int {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : tasks.filter { Self.matches($0, query) }.count
    }

    private static func matches(_ task: TaskItem, _ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || task.title.localizedCaseInsensitiveContains(query) || task.note.localizedCaseInsensitiveContains(query)
    }

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private let didChange: () -> Void

    init(database: DeadlinerDatabase, didChange: @escaping () -> Void = {}) {
        self.database = database
        self.didChange = didChange
    }

    func refresh() {
        tasks = database.tasks.list()
            .filter { !$0.isDeleted && TaskStateMachine.shared.isVisibleInArchive(state: $0.state) }
            .map(TaskItem.init(core:))
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        habits = database.habits.list()
            .filter { !$0.isDeleted && $0.status.name == "ARCHIVED" }
            .map { ArchivedHabit(id: $0.uid, name: $0.name, colorHex: $0.color.map { HabitItem.hex(fromArgb: $0.intValue) }, categoryId: $0.categoryUid) }
        categories = Dictionary(
            database.categories.list().filter { !$0.isDeleted }.map { ($0.uid, CategoryItem(core: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// 恢复已归档的习惯（Core `applyStatusAction(RESTORE)`）。
    func restoreHabit(_ id: String) throws {
        let outcome = database.habits.applyStatusAction(uid: id, action: HabitStatusAction.restore, occurredAt: CoreClock.now()).outcome
        guard ["APPLIED", "NO_OP"].contains(outcome.name) else { throw TaskCommandError.invalidTransition }
        didChange()
    }

    func deleteHabit(_ id: String) {
        database.habits.delete(uid: id, updatedAt: CoreClock.now())
        didChange()
    }
}
