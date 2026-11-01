import Foundation
import Observation
import Shared

/// 概览页的订阅层：持有 Core 的 `IosOverviewStateBridge`（appleMain）。
///
/// 所有统计（今日、历史、时间段、每日 / 每周 / 每月、热力图、上月回顾）都由 Core 的
/// OverviewViewModel 计算；Mac 端只做值类型转换和展示。每次刷新取一次快照，不常驻订阅。
@MainActor
@Observable
final class OverviewStore {
    struct Today: Equatable {
        var completed = 0
        var pending = 0
        var overdue = 0
        var abandoned = 0
    }

    /// Core 的 `pending` 是所有未完成、未放弃的任务，已经包含逾期的；图表用 `onTime` 拆开，避免重复计算。
    struct History: Equatable {
        var completed = 0
        var pending = 0
        var abandoned = 0
        var overdue = 0
        var onTime: Int { max(0, pending - overdue) }
        var total: Int { completed + pending + abandoned }
    }

    enum Period: String, CaseIterable, Identifiable {
        case overnight = "OVERNIGHT", morning = "MORNING", afternoon = "AFTERNOON", evening = "EVENING"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overnight: "凌晨"
            case .morning: "上午"
            case .afternoon: "下午"
            case .evening: "晚上"
            }
        }
    }

    struct PeriodCount: Identifiable, Equatable {
        let period: Period
        let count: Int
        var id: String { period.id }
    }

    /// `date` 为 `yyyy-MM-dd`（每周、每月为起始日）。
    struct DayCount: Identifiable, Equatable {
        let date: String
        let completed: Int
        var overdue = 0
        var id: String { date }
    }

    struct MonthCount: Identifiable, Equatable {
        let monthStart: String
        let total: Int
        let completed: Int
        let overdueCompleted: Int
        var id: String { monthStart }
    }

    struct MonthReview: Equatable {
        var monthStart: String?
        var daily: [DayCount] = []
        var totalTasks = 0
        var completedTasks = 0
        var completionRate = 0.0
        var overdueTasks = 0
        var mostActivePeriod: Period?
        var averageCompletionMinutes: Int?
        var previousTotalTasks = 0
        var previousCompletedTasks = 0
        var previousCompletionRate = 0.0
        var previousOverdueTasks = 0
        var completedTitles: [String] = []
    }

    private(set) var today = Today()
    private(set) var history = History()
    private(set) var periods: [PeriodCount] = Period.allCases.map { PeriodCount(period: $0, count: 0) }
    private(set) var daily: [DayCount] = []
    private(set) var weekly: [DayCount] = []
    private(set) var monthly: [MonthCount] = []
    private(set) var contribution: [DayCount] = []
    private(set) var lastMonth = MonthReview()
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private var bridge: IosOverviewStateBridge?

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    func refresh() {
        if bridge == nil { bridge = IosOverviewStateBridge(database: database) }
        bridge?.load { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }
    }

    func stop() {
        bridge?.close()
        bridge = nil
    }

    private func apply(_ state: OverviewUiState) {
        let summary = state.summary
        today = Today(completed: Int(summary.completedToday), pending: Int(summary.pendingDueFromNow),
                      overdue: Int(summary.overdueToday), abandoned: Int(summary.activeAbandoned))
        let h = state.history
        history = History(completed: Int(h.completed), pending: Int(h.pending), abandoned: Int(h.abandoned), overdue: Int(h.overdue))
        let counts = Dictionary(state.completionBuckets.map { ($0.period.name, Int($0.completedCount)) }, uniquingKeysWith: +)
        periods = Period.allCases.map { PeriodCount(period: $0, count: counts[$0.rawValue] ?? 0) }
        daily = state.daily.map { DayCount(date: $0.date, completed: Int($0.completedCount), overdue: Int($0.overdueCount)) }
        weekly = state.weekly.map { DayCount(date: $0.weekStart, completed: Int($0.completedCount)) }
        monthly = state.monthly.map {
            MonthCount(monthStart: $0.monthStart, total: Int($0.totalCount), completed: Int($0.completedCount),
                       overdueCompleted: Int($0.overdueCompletedCount))
        }
        contribution = state.contribution.map { DayCount(date: $0.date, completed: Int($0.completedCount)) }
        let review = state.lastMonth
        let m = review.metrics
        lastMonth = MonthReview(
            monthStart: review.monthStart,
            daily: review.daily.map { DayCount(date: $0.date, completed: Int($0.completedCount), overdue: Int($0.overdueCount)) },
            totalTasks: Int(m.totalTasks),
            completedTasks: Int(m.completedTasks),
            completionRate: m.completionRate,
            overdueTasks: Int(m.overdueTasks),
            mostActivePeriod: m.mostActivePeriod.flatMap { Period(rawValue: $0.name) },
            averageCompletionMinutes: m.averageCompletionMinutes.map { Int(truncating: $0) },
            previousTotalTasks: Int(m.previousTotalTasks),
            previousCompletedTasks: Int(m.previousCompletedTasks),
            previousCompletionRate: m.previousCompletionRate,
            previousOverdueTasks: Int(m.previousOverdueTasks),
            completedTitles: review.completedTaskTitles
        )
        isLoading = false
        errorMessage = state.error
    }
}
