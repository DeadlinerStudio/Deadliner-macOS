import Foundation
import Observation

/// 应用级状态：Core 容器、各页面的订阅层与写入命令、当前页面。
/// 任何写入完成后调用 `refreshAll()`，让所有页面重新读取 Core。
@MainActor
@Observable
final class AppModel {
    enum Page: String, CaseIterable, Identifiable {
        case tasks, habits, overview, focus, archive, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .tasks: "任务"
            case .habits: "习惯"
            case .overview: "概览"
            case .focus: "专注"
            case .archive: "归档"
            case .settings: "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .tasks: "checklist"
            case .habits: "target"
            case .overview: "chart.bar.xaxis"
            case .focus: "timer"
            case .archive: "archivebox"
            case .settings: "gearshape"
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
    @ObservationIgnored private(set) var overview: OverviewStore!
    @ObservationIgnored private(set) var sync: SyncController!
    /// 系统通知（由 AppDelegate 在启动完成后创建）。
    @ObservationIgnored var notifications: NotificationController?
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
        overview = OverviewStore(database: database)
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
        if page == .overview { overview.refresh() }
    }

    /// 菜单栏与面板的汇总。习惯取今天的状态（习惯页正在看其他日期时，只统计今天的完成度）。
    func menuBarSummary(now: Date) -> MenuBarSummary {
        let today = HabitDates.string(now)
        let todayHabits = habitList.selectedDate == today ? habitList.dailyHabits + habitList.periodGoals : []
        return MenuBarSummary.make(
            tasks: taskList.tasks,
            habits: todayHabits,
            today: habitList.week.first { $0.date == today },
            focusTodaySeconds: focus.today.totalSeconds,
            focusDays: focus.recentDays,
            now: now,
            focusWeekSeconds: focus.thisWeek.totalSeconds
        )
    }

    /// 打开菜单栏面板前：让习惯回到今天，刷新专注统计。
    func prepareMenuBarPanel() {
        let today = HabitDates.string(Date())
        if habitList.selectedDate != today { habitList.select(date: today) }
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
        overview.stop()
        notifications?.stop()
        container.close()
    }
}
