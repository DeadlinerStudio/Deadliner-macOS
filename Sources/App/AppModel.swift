import AppKit
import Foundation
import Observation
import Shared

/// 应用级状态：Core 容器、各页面的订阅层与写入命令、当前页面。
/// 任何写入完成后调用 `refreshAll()`，让所有页面重新读取 Core。
@MainActor
@Observable
final class AppModel {
    enum Page: String, CaseIterable, Identifiable {
        case tasks, habits, capture, overview, focus, archive, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .tasks: "任务"
            case .habits: "习惯"
            case .capture: "灵感"
            case .overview: "概览"
            case .focus: "专注"
            case .archive: "归档"
            case .settings: "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .tasks: "checklist"
            case .habits: "leaf"
            case .capture: "lightbulb"
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
    @ObservationIgnored private(set) var focusTimer: FocusTimerStore!
    /// 任务 / 习惯正在专注计时、又要改变状态时，等待用户确认。
    var timerConflict: TimerConflict?
    /// 每次加 1 播放一次完成动画。
    var celebration = 0
    /// 刚完成的任务，可以撤销（与安卓的「撤销完成」相同）。几秒后消失。
    var undoCompletion: UndoCompletion?
    /// 打开或在剪贴板中识别到的分享链接，等待用户确认导入。
    var pendingShare: PendingShare?
    @ObservationIgnored private var pasteboardChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private(set) var overview: OverviewStore!
    @ObservationIgnored private(set) var capture: CaptureStore!
    @ObservationIgnored private(set) var profile: ProfileStore!
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
        capture = CaptureStore(database: database)
        profile = ProfileStore(database: database)
        sync = SyncController(database: database) { [unowned self] in refreshAll() }
        taskCommands = TaskCommands(database: database) { [unowned self] in refreshAll() }
        categoryCommands = CategoryCommands(database: database) { [unowned self] in refreshAll() }
        habitCommands = HabitCommands(database: database) { [unowned self] in refreshAll() }
        let alarm: FocusAlarmPort = AppDelegate.isRunningTests ? FocusAlarmPortCompanion.shared.NONE : FocusAlarmScheduler()
        focusTimer = FocusTimerStore(database: database, alarm: alarm) { [unowned self] in refreshAll() }
        taskCommands.onTimerConflict = { [unowned self] in timerConflict = $0 }
        habitCommands.onTimerConflict = { [unowned self] in timerConflict = $0 }
        habitCommands.isTiming = { [unowned self] in focusTimer.isTiming(habit: $0) }
        taskCommands.onCompleted = { [unowned self] id in
            celebration += 1
            registerCompletion(id)
        }
    }

    // MARK: - 撤销完成

    struct UndoCompletion: Equatable {
        let token = UUID()
        var ids: [String]
        var title: String
        let startedAt: Date
    }

    static let undoSeconds: TimeInterval = 5

    /// 一次批量完成（1 秒内连续完成）合并成一条提示。
    func registerCompletion(_ id: String, now: Date = Date()) {
        let title = container.database.tasks.find(uid: id)?.title ?? ""
        if var current = undoCompletion, now.timeIntervalSince(current.startedAt) < 1 {
            current.ids.append(id)
            current.title = "\(current.ids.count) 个任务"
            undoCompletion = current
            return
        }
        let next = UndoCompletion(ids: [id], title: "「\(title)」", startedAt: now)
        undoCompletion = next
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoSeconds) { [weak self] in
            if self?.undoCompletion?.token == next.token { self?.undoCompletion = nil }
        }
    }

    /// 撤销：把刚完成的任务改回进行中（Core 的 MARK_COMPLETE 在两者之间切换）。已经被改成其他状态的跳过。
    func undoLastCompletion() {
        guard let undo = undoCompletion else { return }
        undoCompletion = nil
        for id in undo.ids where container.database.tasks.find(uid: id)?.state == TaskState.completed {
            try? taskCommands.toggleComplete(id)
        }
    }

    // MARK: - 分享链接

    struct PendingShare: Identifiable {
        let id = UUID()
        let result: Result<TaskDraft, TaskShareLink.LinkError>
    }

    /// 解析分享链接，交给界面确认（成功时显示任务名，失败时显示原因）。
    func receiveShareLink(_ text: String) {
        do {
            pendingShare = PendingShare(result: .success(try TaskShareLink.decode(text)))
        } catch {
            pendingShare = PendingShare(result: .failure(error as? TaskShareLink.LinkError ?? .corrupted))
        }
    }

    /// 菜单「从剪贴板导入分享链接」：用户主动粘贴。
    func importShareLinkFromPasteboard() {
        pasteboardChangeCount = NSPasteboard.general.changeCount
        if let link = TaskShareLink.fromPasteboard() {
            receiveShareLink(link)
        } else {
            pendingShare = PendingShare(result: .failure(.notALink))
        }
    }

    /// 应用激活时：开启了自动识别、且剪贴板内容变了，才读取剪贴板（与安卓相同）。
    /// macOS 15.4 起先用不读取内容的模式检测，只有剪贴板里是网址时才读取（系统可能询问是否允许）。
    func checkPasteboardForShareLink() {
        let pasteboard = NSPasteboard.general
        guard UserDefaults.standard.bool(forKey: ShareLinkSettings.detectClipboardKey),
              pasteboard.changeCount != pasteboardChangeCount, pendingShare == nil else { return }
        pasteboardChangeCount = pasteboard.changeCount
        let read = { [weak self] in
            guard let self, let link = TaskShareLink.fromPasteboard(pasteboard), link != TaskShareLink.lastCopied else { return }
            receiveShareLink(link)
        }
        if #available(macOS 15.4, *) {
            // 系统剪贴板对象可以在任意线程使用。
            nonisolated(unsafe) let board = pasteboard
            _Concurrency.Task {
                let key: PartialKeyPath<NSPasteboard.DetectedValues> = \.probableWebURL
                guard let found = try? await board.detectedPatterns(for: [key]), found.contains(key) else { return }
                read()
            }
        } else {
            read()
        }
    }

    /// 确认导入：在任务页打开编辑器（新任务，保存后才写入）。
    func acceptShare(_ draft: TaskDraft) {
        pendingShare = nil
        page = .tasks
        taskList.editor = .init(draft: draft)
    }

    /// 确认冲突：先结束并保存这次专注，再执行原来的操作（Core 在同一事务中完成）。
    func resolveTimerConflict(_ conflict: TimerConflict, completion: @escaping (String?) -> Void) {
        if conflict.isHabit {
            focusTimer.resolveHabitChange(conflict.targetId, delete: conflict.delete, completion: completion)
        } else {
            focusTimer.resolveTaskChange(conflict.targetId, action: conflict.action, delete: conflict.delete, completion: completion)
        }
    }

    func start() {
        taskList.start()
        habitList.start()
        archive.refresh()
        focus.refresh()
        focusTimer.start()
        sync.start()
    }

    func refreshAll(except skipped: Page? = nil) {
        if skipped != .tasks { taskList.refresh() }
        if skipped != .habits { habitList.refresh() }
        archive.refresh()
        focus.refresh()
        capture.refresh()
        profile.refresh()
        if page == .overview { overview.refresh() }
        notifications?.scheduleDailySummary()
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
        focusTimer.stop()
        notifications?.stop()
        container.close()
    }
}
