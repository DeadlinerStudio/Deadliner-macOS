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
        /// 百分数（0～100），与 Core 一致。
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

    /// 选定月份的完整数据（Core `loadMonth`）。
    struct MonthDetail: Equatable {
        var review: MonthReview
        var distribution: History
        var archivedTasks: Int
        var archivedHabits: Int
    }

    /// 专注时长的一个点（某天、某周或某月）。`start` 为 `yyyy-MM-dd`。
    struct FocusPoint: Identifiable, Equatable {
        let start: String
        let seconds: Int
        var id: String { start }
    }

    /// 某个时间范围内的专注（Core `focusStatistics.snapshot`）。
    struct FocusRange: Equatable {
        var totalSeconds = 0
        var sessions = 0
        var activeDays = 0
        var daily: [FocusPoint] = []
        /// 按分类的时长，从多到少；没有分类的记为「未分类」。
        var categories: [(title: String, seconds: Int)] = []

        static func == (a: FocusRange, b: FocusRange) -> Bool {
            a.totalSeconds == b.totalSeconds && a.sessions == b.sessions && a.activeDays == b.activeDays && a.daily == b.daily
                && a.categories.map(\.title) == b.categories.map(\.title) && a.categories.map(\.seconds) == b.categories.map(\.seconds)
        }

        func seconds(on date: String) -> Int { daily.first { $0.start == date }?.seconds ?? 0 }
    }

    /// 趋势用的专注序列（Core `focusStatistics.overview`）。
    struct FocusTrend: Equatable {
        var todaySeconds = 0
        var weekSeconds = 0
        var daily: [FocusPoint] = []
        var monthly: [FocusPoint] = []
        var rollingWeekly: [FocusPoint] = []
    }

    /// 自定义日期范围的数据（Core `loadRange`）。`asOf` 之后的日期没有完成记录。
    struct RangeDetail: Equatable {
        var start: String
        var endExclusive: String
        var asOf: String
        var review: MonthReview
        var distribution: History
        var periods: [PeriodCount]
        /// 截至今天的部分（用于汇总数字，避免把未来的空白日计入日均）。
        var elapsedDaily: [DayCount] { review.daily.filter { $0.date <= asOf } }
        var extendsIntoFuture: Bool { endExclusive > asOf && review.daily.contains { $0.date > asOf } }
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
    private(set) var month: MonthDetail?
    private(set) var monthError: String?
    private(set) var range: RangeDetail?
    private(set) var rangeError: String?
    private(set) var focus = FocusTrend()
    /// 所选月份、自定义范围、近 30 天的专注。
    private(set) var focusMonth: FocusRange?
    private(set) var focusCustom: FocusRange?
    private(set) var focusLast30: FocusRange?
    /// 上个月每天的完成数（用于「较上月同期」）。
    private(set) var previousMonthDaily: [DayCount] = []
    /// 工作台所选区间的专注。
    private(set) var focusInterval: FocusRange?
    /// 所选月份 / 区间内完成的任务按完成时机的数量（Mac 端推算，见 `CompletionTiming`）。
    private(set) var monthTiming: [CompletionTiming: Int] = [:]
    private(set) var intervalTiming: [CompletionTiming: Int] = [:]
    /// 每天 / 每月完成的任务按完成时机的数量（键为 `yyyy-MM-dd` / 月初 `yyyy-MM-01`），用于近期趋势与每月趋势。
    private(set) var dayTimings: [String: [CompletionTiming: Int]] = [:]
    private(set) var monthTimings: [String: [CompletionTiming: Int]] = [:]
    private(set) var monthLoading = false
    private(set) var previousMonth: MonthReview?
    private(set) var comparisonError: String?
    private(set) var annual: [DayCount] = []
    /// 今年每天的专注秒数（键为 `yyyy-MM-dd`），用于热力图悬停提示。
    private(set) var annualFocus: [String: Int] = [:]
    private(set) var annualError: String?
    private(set) var annualLoading = false
    private(set) var interval: MonthReview?
    private(set) var intervalDistribution = History()
    private(set) var intervalPeriods: [PeriodCount] = []
    private(set) var intervalError: String?
    private(set) var intervalLoading = false
    @ObservationIgnored private var selectedMonth: String?
    @ObservationIgnored private var selectedInterval: (String, String)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var monthGeneration = 0
    @ObservationIgnored private var intervalGeneration = 0
    @ObservationIgnored private var annualGeneration = 0

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private var bridge: IosOverviewStateBridge?

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    func refresh() {
        if bridge == nil { bridge = IosOverviewStateBridge(database: database) }
        generation += 1
        let request = generation
        isLoading = true
        bridge?.load { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.generation == request else { return }
                self.apply(state)
            }
        }
        refreshTimings()
        if let selectedMonth { loadMonth(selectedMonth) }
        if let selectedInterval { loadInterval(start: selectedInterval.0, end: selectedInterval.1) }
        loadAnnual()
        refreshFocus()
    }

    private func refreshFocus() {
        let overview = database.focusStatistics.overview()
        func points(_ list: [FocusDurationPoint]) -> [FocusPoint] {
            list.map { FocusPoint(start: $0.startDate, seconds: Int($0.durationSeconds)) }
        }
        focus = FocusTrend(todaySeconds: Int(overview.today.totalDurationSeconds),
                           weekSeconds: Int(overview.thisWeek.totalDurationSeconds),
                           daily: points(overview.daily), monthly: points(overview.monthly),
                           rollingWeekly: points(overview.rollingWeekly))
        let today = Calendar.current.startOfDay(for: Date())
        focusLast30 = focusRange(DateRange(start: today.addingTimeInterval(-86400 * 29), end: today))
    }

    /// 某个日期范围的专注统计（起止都包含）。
    func focusRange(_ selection: DateRange) -> FocusRange {
        focusRange(start: DateRange.isoString(selection.start), endExclusive: DateRange.isoString(selection.endExclusive()))
    }

    /// 某个日期范围的专注统计（`yyyy-MM-dd`，结束日期不包含）。
    func focusRange(start: String, endExclusive: String) -> FocusRange {
        let range = FocusStatisticsDateRange(startDate: start, endDateExclusive: endExclusive)
        let snapshot = database.focusStatistics.snapshot(query: FocusStatisticsQuery(range: range, taskUid: nil, categoryUid: nil,
                                                                                    target: nil, targetKind: nil))
        return FocusRange(
            totalSeconds: Int(snapshot.summary.totalDurationSeconds),
            sessions: Int(snapshot.summary.sessionCount),
            activeDays: Int(snapshot.summary.activeDayCount),
            daily: snapshot.daily.map { FocusPoint(start: $0.startDate, seconds: Int($0.durationSeconds)) },
            categories: snapshot.categories
                .map { (title: $0.categoryTitle ?? "未分类", seconds: Int($0.durationSeconds)) }
                .filter { $0.seconds > 0 }
                .sorted { $0.seconds > $1.seconds }
        )
    }

    /// 读取某个月（`yyyy-MM-01`）的数据；结果在 `month`，失败时在 `monthError`。
    func loadMonth(_ monthStart: String) {
        if bridge == nil { bridge = IosOverviewStateBridge(database: database) }
        if let start = OverviewDates.date(monthStart), let end = Calendar.current.date(byAdding: .month, value: 1, to: start) {
            monthTiming = timing(from: DateRange.isoString(start), to: DateRange.isoString(end))
        }
        selectedMonth = monthStart
        monthGeneration += 1
        let request = monthGeneration
        monthError = nil
        if let start = OverviewDates.date(monthStart),
           let end = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start) {
            focusMonth = focusRange(DateRange(start: start, end: end))
        }
        previousMonthDaily = []
        if let previous = OverviewRange.month(monthStart, offset: -1) {
            bridge?.loadMonth(monthStart: previous, onState: { [weak self] state in
                MainActor.assumeIsolated {
                    self?.previousMonthDaily = state.daily.map { DayCount(date: $0.date, completed: Int($0.completedCount), overdue: Int($0.overdueCount)) }
                }
            }, onError: { _ in })
        }
        comparisonError = nil
        monthLoading = true
        month = nil
        previousMonth = nil
        bridge?.loadMonth(monthStart: monthStart, onState: { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.monthGeneration == request else { return }
                self.monthLoading = false
                self.month = MonthDetail(
                    review: Self.review(state.review),
                    distribution: Self.exclusiveHistory(state.statusDistribution),
                    archivedTasks: Int(state.archivedTaskCount),
                    archivedHabits: Int(state.archivedHabitCount)
                )
            }
        }, onError: { [weak self] message in
            MainActor.assumeIsolated {
                guard let self, self.monthGeneration == request else { return }
                self.monthLoading = false
                self.monthError = message
            }
        })
        guard let date = OverviewDates.date(monthStart) else { return }
        let previous = OverviewPeriod.key(OverviewPeriod.shift(date, months: -1))
        bridge?.loadMonth(monthStart: previous, onState: { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.monthGeneration == request else { return }
                self.previousMonth = Self.review(state.review)
            }
        }, onError: { [weak self] message in
            MainActor.assumeIsolated {
                guard let self, self.monthGeneration == request else { return }
                self.comparisonError = message
            }
        })
    }

    /// 读取自定义范围（起止都包含在内）。
    func loadRange(_ selection: DateRange) {
        if bridge == nil { bridge = IosOverviewStateBridge(database: database) }
        rangeError = nil
        focusCustom = focusRange(selection)
        let start = DateRange.isoString(selection.start)
        let endExclusive = DateRange.isoString(selection.endExclusive())
        bridge?.loadRange(startDate: start, endDateExclusive: endExclusive, onState: { [weak self] state in
            MainActor.assumeIsolated {
                let counts = Dictionary(state.completionBuckets.map { ($0.period.name, Int($0.completedCount)) }, uniquingKeysWith: +)
                self?.range = RangeDetail(
                    start: state.startDate,
                    endExclusive: state.endDateExclusive,
                    asOf: state.asOfDate,
                    review: Self.review(monthStart: nil, daily: state.daily, metrics: state.metrics, titles: state.completedTaskTitles),
                    distribution: Self.history(state.statusDistribution),
                    periods: Period.allCases.map { PeriodCount(period: $0, count: counts[$0.rawValue] ?? 0) }
                )
            }
        }, onError: { [weak self] message in
            MainActor.assumeIsolated {
                self?.range = nil
                self?.rangeError = message
            }
        })
    }

    func loadInterval(start: String, end: String) {
        if bridge == nil { bridge = IosOverviewStateBridge(database: database) }
        selectedInterval = (start, end)
        intervalGeneration += 1
        let request = intervalGeneration
        intervalLoading = true
        intervalError = nil
        interval = nil
        // 无效范围交给 Core 的 loadRange 报错；不传给专注统计，避免未捕获的 Kotlin 异常。
        focusInterval = start < end ? focusRange(start: start, endExclusive: end) : nil
        intervalTiming = timing(from: start, to: end)
        bridge?.loadRange(startDate: start, endDateExclusive: end, onState: { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.intervalGeneration == request else { return }
                self.intervalLoading = false
                self.interval = Self.metrics(state.metrics, monthStart: nil,
                    daily: state.daily.map { DayCount(date: $0.date, completed: Int($0.completedCount), overdue: Int($0.overdueCount)) },
                    titles: state.completedTaskTitles)
                self.intervalDistribution = Self.exclusiveHistory(state.statusDistribution)
                let counts = Dictionary(state.completionBuckets.map { ($0.period.name, Int($0.completedCount)) }, uniquingKeysWith: +)
                self.intervalPeriods = Period.allCases.map { PeriodCount(period: $0, count: counts[$0.rawValue] ?? 0) }
            }
        }, onError: { [weak self] message in
            MainActor.assumeIsolated {
                guard let self, self.intervalGeneration == request else { return }
                self.intervalLoading = false
                self.intervalError = message
            }
        })
    }

    private func loadAnnual() {
        annualGeneration += 1
        let request = annualGeneration
        annualLoading = true
        annualError = nil
        let now = Date()
        let start = OverviewPeriod.calendar.date(from: OverviewPeriod.calendar.dateComponents([.year], from: now))!
        let end = OverviewPeriod.calendar.date(byAdding: .day, value: 1, to: now)!
        annualFocus = Dictionary(focusRange(start: OverviewPeriod.key(start), endExclusive: OverviewPeriod.key(end)).daily
            .map { ($0.start, $0.seconds) }, uniquingKeysWith: +)
        bridge?.loadRange(startDate: OverviewPeriod.key(start), endDateExclusive: OverviewPeriod.key(end), onState: { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.annualGeneration == request else { return }
                self.annualLoading = false
                self.annual = state.daily.map { DayCount(date: $0.date, completed: Int($0.completedCount)) }
            }
        }, onError: { [weak self] message in
            MainActor.assumeIsolated {
                guard let self, self.annualGeneration == request else { return }
                self.annualLoading = false
                self.annualError = message
            }
        })
    }

    /// 月/区间状态互斥；旧 History 的 pending 则含逾期。
    static func exclusiveHistory(_ h: OverviewHistory) -> History {
        History(completed: Int(h.completed), pending: Int(h.pending + h.overdue),
                abandoned: Int(h.abandoned), overdue: Int(h.overdue))
    }

    private func refreshTimings() {
        let calendar = Calendar.current
        var days: [String: [CompletionTiming: Int]] = [:]
        var months: [String: [CompletionTiming: Int]] = [:]
        for task in database.tasks.list() where !task.isDeleted {
            let item = TaskItem(core: task)
            guard let done = item.completedAt, let timing = CompletionTiming.of(item, calendar: calendar) else { continue }
            let day = calendar.startOfDay(for: done)
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: done)) ?? day
            days[DateRange.isoString(day), default: [:]][timing, default: 0] += 1
            months[DateRange.isoString(month), default: [:]][timing, default: 0] += 1
        }
        dayTimings = days
        monthTimings = months
    }

    /// 完成时间在 `[start, end)`（本地日期 `yyyy-MM-dd`）内的任务按完成时机计数。
    func timing(from start: String, to end: String) -> [CompletionTiming: Int] {
        guard let from = OverviewDates.date(start), let to = OverviewDates.date(end) else { return [:] }
        let tasks = database.tasks.list().filter { !$0.isDeleted }.map(TaskItem.init(core:))
        return CompletionTiming.counts(tasks, from: from, to: to)
    }

    func stop() {
        generation += 1
        monthGeneration += 1
        intervalGeneration += 1
        annualGeneration += 1
        bridge?.close()
        bridge = nil
    }

    private func apply(_ state: OverviewUiState) {
        let summary = state.summary
        today = Today(completed: Int(summary.completedToday), pending: Int(summary.pendingDueFromNow),
                      overdue: Int(summary.overdueToday), abandoned: Int(summary.activeAbandoned))
        history = Self.history(state.history)
        let counts = Dictionary(state.completionBuckets.map { ($0.period.name, Int($0.completedCount)) }, uniquingKeysWith: +)
        periods = Period.allCases.map { PeriodCount(period: $0, count: counts[$0.rawValue] ?? 0) }
        daily = state.daily.map { DayCount(date: $0.date, completed: Int($0.completedCount), overdue: Int($0.overdueCount)) }
        weekly = state.weekly.map { DayCount(date: $0.weekStart, completed: Int($0.completedCount)) }
        monthly = state.monthly.map {
            MonthCount(monthStart: $0.monthStart, total: Int($0.totalCount), completed: Int($0.completedCount),
                       overdueCompleted: Int($0.overdueCompletedCount))
        }
        contribution = state.contribution.map { DayCount(date: $0.date, completed: Int($0.completedCount)) }
        lastMonth = Self.review(state.lastMonth)
        isLoading = false
        errorMessage = state.error
    }

    private static func history(_ h: OverviewHistory) -> History {
        History(completed: Int(h.completed), pending: Int(h.pending), abandoned: Int(h.abandoned), overdue: Int(h.overdue))
    }

    private static func review(_ review: OverviewLastMonth) -> MonthReview {
        metrics(review.metrics, monthStart: review.monthStart,
                daily: review.daily.map { DayCount(date: $0.date, completed: Int($0.completedCount), overdue: Int($0.overdueCount)) },
                titles: review.completedTaskTitles)
    }

    private static func review(monthStart: String?, daily: [OverviewDailyStat], metrics m: OverviewMonthlyMetrics,
                               titles: [String]) -> MonthReview {
        metrics(m, monthStart: monthStart,
                daily: daily.map { DayCount(date: $0.date, completed: Int($0.completedCount), overdue: Int($0.overdueCount)) },
                titles: titles)
    }

    private static func metrics(_ m: OverviewMonthlyMetrics, monthStart: String?, daily: [DayCount], titles: [String]) -> MonthReview {
        MonthReview(
            monthStart: monthStart,
            daily: daily,
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
            completedTitles: titles
        )
    }
}

extension OverviewStore {
    /// 「较上月同期」：本月 1 日到今天的完成数，与上月 1 日到同一日期（上月没有这天时取月末）比较。
    /// 只用于当前月份；返回 (本月, 上月同期)。
    static func samePeriod(current: [DayCount], previous: [DayCount], today: Date, calendar: Calendar = .current) -> (Int, Int)? {
        guard !current.isEmpty, !previous.isEmpty else { return nil }
        let day = calendar.component(.day, from: today)
        let thisMonth = current.prefix(day).map(\.completed).reduce(0, +)
        let lastMonth = previous.prefix(min(day, previous.count)).map(\.completed).reduce(0, +)
        return (thisMonth, lastMonth)
    }
}
