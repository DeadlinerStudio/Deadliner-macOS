import Foundation
import Observation
import Shared

/// 任务列表的订阅层：持有 Core 的 `IosTaskListStateBridge`（appleMain），
/// 把 `TaskListUiState` 转成界面使用的 `TaskItem`。
///
/// 读取和排序的依据都来自 Core：主列表可见性用 `TaskStateMachine.isVisibleInMainList`，
/// 排序与 Core `TaskListViewModel.getFilteredTasks` 一致。
@MainActor
@Observable
final class TaskListStore {
    enum SortOrder: String, CaseIterable, Identifiable {
        case dueDate, createdAt, title
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dueDate: "截止时间"
            case .createdAt: "创建时间"
            case .title: "标题"
            }
        }
    }

    private(set) var tasks: [TaskItem] = []
    private(set) var categories: [String: CategoryItem] = [:]
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var searchText = ""
    var sortOrder: SortOrder = .dueDate
    /// 分类筛选：nil 为全部，`uncategorized` 为未分类，其余为分类 ID。
    var categoryFilter: String?
    static let uncategorized = "__uncategorized"
    /// 完成时机筛选（超前 / 提前 / 按时 / 逾期完成）；nil 为不筛选。
    var timingFilter: CompletionTiming?
    /// 正在打开的编辑器（新建或编辑）。
    var editor: EditorRequest?

    struct EditorRequest: Identifiable {
        let id = UUID()
        let draft: TaskDraft
    }

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private var bridge: IosTaskListStateBridge?
    @ObservationIgnored private var coreTasks: [TaskItem] = []

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    /// 开始接收状态，并做第一次读取。
    func start() {
        guard bridge == nil else { return refresh() }
        let bridge = IosTaskListStateBridge(taskRepository: database.tasks, notificationOrchestrator: nil)
        self.bridge = bridge
        loadCategories()
        // Core 在主线程回调（Dispatchers.Main）。
        bridge.start { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }
    }

    /// 在别处写入（例如同步完成）之后重新读取。
    func refresh() {
        loadCategories()
        bridge?.refresh()
    }

    func stop() {
        bridge?.close()
        bridge = nil
    }

    /// 经过搜索、分类筛选和排序后用于显示的任务。
    var visibleTasks: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered = query.isEmpty ? coreTasks : coreTasks.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query)
        }
        if let categoryFilter {
            filtered = filtered.filter {
                categoryFilter == Self.uncategorized ? ($0.categoryId.flatMap { categories[$0] } == nil) : $0.categoryId == categoryFilter
            }
        }
        if let timingFilter {
            filtered = filtered.filter { CompletionTiming.of($0) == timingFilter }
        }
        return Self.sorted(filtered, by: sortOrder)
    }

    private func apply(_ state: TaskListUiState) {
        isLoading = state.isLoading
        errorMessage = state.error
        coreTasks = state.tasks
            .filter { !$0.isDeleted && TaskStateMachine.shared.isVisibleInMainList(state: $0.state) }
            .map(TaskItem.init(core:))
        tasks = coreTasks
    }

    private func loadCategories() {
        let list = database.categories.list().filter { !$0.isDeleted }.map(CategoryItem.init(core:))
        categories = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 与 Core `TaskListViewModel.getFilteredTasks` 相同：进行中在前，标星在前，再按所选字段，最后按创建时间。
    static func sorted(_ items: [TaskItem], by order: SortOrder) -> [TaskItem] {
        items.sorted { a, b in
            if (a.state == .active) != (b.state == .active) { return a.state == .active }
            if a.isStarred != b.isStarred { return a.isStarred }
            switch order {
            case .dueDate:
                let da = a.dueAt ?? .distantPast, db = b.dueAt ?? .distantPast
                if da != db { return da < db }
            case .createdAt:
                let ca = a.createdAt ?? .distantPast, cb = b.createdAt ?? .distantPast
                if ca != cb { return ca > cb }
            case .title:
                let result = a.title.localizedCaseInsensitiveCompare(b.title)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
        }
    }
}
