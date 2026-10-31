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
