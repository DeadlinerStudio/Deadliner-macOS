import Foundation
import Observation
import Shared

/// 习惯页的订阅层：持有 Core 的 `IosHabitListStateBridge`（appleMain）。
///
/// 分组、当日状态、一周概览都由 Core 的 HabitListViewModel 计算；
/// 打卡调用 Core 的主操作（勾选型打卡 / 计量型累加，完成后再点清零），Mac 端不自行判断。
@MainActor
@Observable
final class HabitListStore {
    private(set) var dailyHabits: [HabitItem] = []
    private(set) var periodGoals: [HabitItem] = []
    private(set) var upcomingReviews: [HabitItem] = []
    private(set) var week: [HabitDay] = []
    private(set) var selectedDate = ""
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var searchText = ""
    /// 正在打开的习惯编辑器（新建或编辑）。
    var editor: EditorRequest?

    struct EditorRequest: Identifiable {
        let id = UUID()
        let draft: HabitDraft
    }

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private var bridge: IosHabitListStateBridge?
    @ObservationIgnored private let didChange: () -> Void
    /// 上一次认定的「今天」：跨天后，如果还停在旧的今天，就跟到新的今天。
    @ObservationIgnored private var followedToday = HabitDates.string(Date())

    init(database: DeadlinerDatabase, didChange: @escaping () -> Void = {}) {
        self.database = database
        self.didChange = didChange
    }

    func start() {
        guard bridge == nil else { return refresh() }
        let bridge = IosHabitListStateBridge(habitRepository: database.habits, notificationOrchestrator: nil)
        self.bridge = bridge
        bridge.start { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }
    }

    func refresh() { bridge?.refresh() }

    func stop() {
        bridge?.close()
        bridge = nil
    }

    /// 切换查看的日期（`yyyy-MM-dd`）。
    func select(date: String) { bridge?.selectDate(rawDate: date) }

    /// 跨天处理：Core 记住的是上次选中的日期，应用一直开着时不会自己换到新的一天，
    /// 日期条也只显示所选日期那一周。所以停在旧的「今天」时跟到新的今天；用户特意查看的其他日期不动。
    func rollOverIfNeeded(now: Date = Date()) {
        let today = HabitDates.string(now)
        guard bridge != nil, today != followedToday else { return }
        let previous = followedToday
        followedToday = today
        if selectedDate.isEmpty || selectedDate == previous { select(date: today) }
    }

    func goToToday(now: Date = Date()) {
        followedToday = HabitDates.string(now)
        select(date: followedToday)
    }

    /// 前后翻周（保持星期几不变）。
    func shiftWeek(by weeks: Int) {
        guard let date = HabitDates.date(selectedDate),
              let target = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: date) else { return }
        select(date: HabitDates.string(target))
    }

    /// 对所选日期执行 Core 的主操作。
    func applyPrimaryAction(_ habit: HabitItem) {
        guard habit.canApplyPrimaryAction else { return }
        bridge?.applyPrimaryAction(habitUid: habit.id)
        didChange()
    }

    /// 所选日期的完成度。
    var selectedDay: HabitDay? { week.first { $0.date == selectedDate } }

    func filtered(_ items: [HabitItem]) -> [HabitItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query) }
    }

    private func apply(_ state: HabitListUiState) {
        isLoading = state.isLoading
        errorMessage = state.error
        selectedDate = state.selectedDate
        dailyHabits = state.dailyHabits.map(HabitItem.init(core:))
        periodGoals = state.periodGoals.map(HabitItem.init(core:))
        upcomingReviews = state.upcomingReviews.map(HabitItem.init(core:))
        week = state.weekOverview.map(HabitDay.init(core:))
    }
}
