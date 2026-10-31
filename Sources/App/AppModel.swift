import Foundation
import Observation

/// 应用级状态：Core 容器、各页面的订阅层与写入命令、当前页面。
/// 任何写入完成后调用 `refreshAll()`，让所有页面重新读取 Core。
@MainActor
@Observable
final class AppModel {
    enum Page: String, CaseIterable, Identifiable {
        case tasks, habits, focus, archive, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .tasks: "任务"
            case .habits: "习惯"
            case .focus: "专注"
            case .archive: "存档"
            case .settings: "设置"
            }
        }
    }

    var page: Page = .tasks
    /// 每次 +1 时，当前页面的搜索框获得焦点（⌘F）。
    var searchFocusRequest = 0

    @ObservationIgnored let container: MacCoreContainer
    @ObservationIgnored private(set) var taskList: TaskListStore!
    @ObservationIgnored private(set) var habitList: HabitListStore!
    @ObservationIgnored private(set) var archive: ArchiveStore!
    @ObservationIgnored private(set) var focus: FocusStore!
    @ObservationIgnored private(set) var sync: SyncController!
    @ObservationIgnored private(set) var taskCommands: TaskCommands!
    @ObservationIgnored private(set) var categoryCommands: CategoryCommands!
    @ObservationIgnored private(set) var habitCommands: HabitCommands!

    init(container: MacCoreContainer) {
        self.container = container
        let database = container.database
        taskList = TaskListStore(database: database)
        habitList = HabitListStore(database: database) { [unowned self] in refreshAll(except: .habits) }
        archive = ArchiveStore(database: database) { [unowned self] in refreshAll() }
        focus = FocusStore(database: database)
        sync = SyncController(database: database) { [unowned self] in refreshAll() }
        taskCommands = TaskCommands(database: database) { [unowned self] in refreshAll() }
        categoryCommands = CategoryCommands(database: database) { [unowned self] in refreshAll() }
        habitCommands = HabitCommands(database: database) { [unowned self] in refreshAll() }
    }

    func start() {
        taskList.start()
        habitList.start()
        archive.refresh()
        focus.refresh()
        sync.start()
    }

    func refreshAll(except skipped: Page? = nil) {
        if skipped != .tasks { taskList.refresh() }
        if skipped != .habits { habitList.refresh() }
        archive.refresh()
        focus.refresh()
    }

    func newTask() {
        page = .tasks
        taskList.editor = .init(draft: TaskDraft())
    }

    func stop() {
        sync.stop()
        taskList.stop()
        habitList.stop()
        container.close()
    }
}
