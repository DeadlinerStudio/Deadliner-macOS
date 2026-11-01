import Charts
import SwiftUI

/// 概览页：与 iOS 端相同的三部分（总览 / 趋势 / 月度），数据全部来自 Core。
/// 不包含 iOS 的「AI 月度洞察」（AI 暂缓）。
struct OverviewView: View {
    let store: OverviewStore
    @AppStorage(CardLayout.storageKey) private var layoutRaw = CardLayout.single.rawValue
    @AppStorage("overview.section") private var sectionRaw = OverviewSection.stats.rawValue
    @Environment(\.palette) private var t

    var body: some View {
        OverviewContent(
            store: store,
            section: OverviewSection(rawValue: sectionRaw) ?? .stats,
            layout: CardLayout(rawValue: layoutRaw) ?? .single
        )
        .topAtmosphere(t.primary)
        .navigationTitle("概览")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("分区", selection: $sectionRaw) {
                    ForEach(OverviewSection.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem {
                Button { store.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .help("重新计算统计")
            }
        }
        .onAppear { store.refresh() }
    }
}

enum OverviewSection: String, CaseIterable, Identifiable {
    case stats, trends, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stats: "总览"
        case .trends: "趋势"
        case .month: "月度"
        }
    }
}

/// 页面主体，便于截图测试（不依赖 Core 的值类型都在 OverviewStore 中）。
struct OverviewContent: View {
    let store: OverviewStore
    let section: OverviewSection
    var layout: CardLayout = .single
    @Environment(\.palette) private var t

    var body: some View {
        ScrollView(.vertical) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(t.error)
                    .padding(.top, 40)
            } else {
                // 同一行的卡片顶端对齐（默认居中，高度不同时会错位）。
                LazyVGrid(columns: layout.columns.map { var item = $0; item.alignment = .top; return item },
                          alignment: .leading, spacing: MiuixCard.gap) {
                    switch section {
                    case .stats:
                        OverviewTodayCard(today: store.today)
                        OverviewPeriodCard(periods: store.periods)
                        OverviewHistoryCard(history: store.history)
                    case .trends:
                        OverviewHeatmapCard(days: store.contribution)
                        OverviewDailyCard(days: store.daily)
                        OverviewMonthlyCard(months: store.monthly)
                        OverviewWeeklyCard(weeks: store.weekly)
                    case .month:
                        OverviewMetricsCard(review: store.lastMonth)
                        OverviewMonthMapCard(review: store.lastMonth)
                        if !store.lastMonth.completedTitles.isEmpty {
                            OverviewTitlesCard(review: store.lastMonth)
                        }
                    }
                }
                .readableWidth(layout.maxContentWidth)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .overlay {
            if store.isLoading { ProgressView() }
        }
    }
}

// MARK: - 颜色与日期

/// 概览中各状态的颜色：已完成为绿色，未完成为主色，逾期为错误色，放弃为灰色。
struct OverviewColors {
    let t: DeadlinerPalette
    var completed: Color { Color(hex: 0x10B981) }
    var pending: Color { t.primary }
    var overdue: Color { t.error }
    var abandoned: Color { t.abandoned }
}

enum OverviewDates {
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ raw: String) -> Date? { iso.date(from: raw) }

    static func label(_ raw: String, _ format: String) -> String {
        guard let date = date(raw) else { return raw }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f.string(from: date)
    }
}

// MARK: - 卡片容器

struct OverviewCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    @Environment(\.palette) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(t.onSurfaceVariant)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.groupBg, in: RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
    }
}

private struct EmptyChart: View {
    var text = "暂无数据"
    @Environment(\.palette) private var t

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(t.onSurfaceVariant)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

private struct BigNumber: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.palette) private var t

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(t.onSurfaceVariant)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 总览

struct OverviewTodayCard: View {
    let today: OverviewStore.Today
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        OverviewCard(title: "今日概况") {
            HStack {
                BigNumber(title: "今日完成", value: "\(today.completed)", tint: c.completed)
                BigNumber(title: "待完成", value: "\(today.pending)", tint: c.pending)
                BigNumber(title: "今日逾期", value: "\(today.overdue)", tint: c.overdue)
                BigNumber(title: "已放弃", value: "\(today.abandoned)", tint: c.abandoned)
            }
        }
    }
}

struct OverviewPeriodCard: View {
    let periods: [OverviewStore.PeriodCount]
    @Environment(\.palette) private var t

    var body: some View {
        OverviewCard(title: "完成时间分布") {
            if periods.allSatisfy({ $0.count == 0 }) {
                EmptyChart(text: "暂无已完成数据")
            } else {
                let peak = max(1, periods.map(\.count).max() ?? 1)
                VStack(spacing: 12) {
                    ForEach(periods) { item in
                        HStack(spacing: 12) {
                            Text(item.period.title).font(.callout).frame(width: 36, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(t.onSurface.opacity(0.06))
                                    Capsule().fill(t.primary.gradient)
                                        .frame(width: item.count == 0 ? 0 : max(10, proxy.size.width * Double(item.count) / Double(peak)))
                                }
                            }
                            .frame(height: 12)
                            Text("\(item.count)").font(.callout.monospacedDigit()).foregroundStyle(t.onSurfaceVariant)
                                .frame(minWidth: 24, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

struct OverviewHistoryCard: View {
    let history: OverviewStore.History
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        let slices: [(String, Int, Color)] = [
            ("已完成", history.completed, c.completed),
            ("未完成", history.onTime, c.pending),
            ("逾期", history.overdue, c.overdue),
            ("已放弃", history.abandoned, c.abandoned),
        ]
        OverviewCard(title: "历史统计") {
            if history.total == 0 {
                EmptyChart()
            } else {
                HStack(spacing: 24) {
                    Chart(slices, id: \.0) { slice in
                        SectorMark(angle: .value("数量", slice.1), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(slice.2)
                            .cornerRadius(4)
                    }
                    .chartBackground { _ in
                        VStack(spacing: 0) {
                            Text("总计").font(.caption).foregroundStyle(t.onSurfaceVariant)
                            Text("\(history.total)").font(.title2.bold())
                        }
                    }
                    .frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(slices, id: \.0) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.2).frame(width: 9, height: 9)
                                Text(slice.0).font(.callout)
                                Spacer(minLength: 12)
                                Text("\(slice.1)").font(.callout.monospacedDigit()).foregroundStyle(t.onSurfaceVariant)
                            }
                        }
                    }
                    .frame(maxWidth: 220)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - 趋势

struct OverviewHeatmapCard: View {
    let days: [OverviewStore.DayCount]
    @Environment(\.palette) private var t

    var body: some View {
        OverviewCard(title: "活跃热力图", subtitle: days.isEmpty ? nil : "\(days.count) 天内") {
            if days.isEmpty {
                EmptyChart()
            } else {
                let weeks = Self.weeks(days)
                let peak = max(1, days.map(\.completed).max() ?? 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(weeks.indices, id: \.self) { w in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { d in
                                    let day = weeks[w][d]
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(color(day?.completed, peak: peak))
                                        .frame(width: 12, height: 12)
                                        .help(day.map { "\($0.date)：完成 \($0.completed)" } ?? "")
                                }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
                HStack(spacing: 4) {
                    Spacer()
                    Text("少").font(.caption2).foregroundStyle(t.onSurfaceVariant)
                    ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2).fill(color(level, peak: 4)).frame(width: 10, height: 10)
                    }
                    Text("多").font(.caption2).foregroundStyle(t.onSurfaceVariant)
                }
            }
        }
    }

    private func color(_ count: Int?, peak: Int) -> Color {
        guard let count else { return .clear }
        if count == 0 { return t.onSurface.opacity(0.07) }
        return t.primary.opacity(0.25 + 0.75 * Double(count) / Double(peak))
    }

    /// 按周排列（每列一周，周一在上）；首周前面空出的日子为 nil。
    static func weeks(_ days: [OverviewStore.DayCount]) -> [[OverviewStore.DayCount?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        guard let first = days.first.flatMap({ OverviewDates.date($0.date) }) else { return [] }
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        let cells: [OverviewStore.DayCount?] = Array(repeating: nil, count: offset) + days.map { $0 }
        return stride(from: 0, to: cells.count, by: 7).map { start in
            let slice = Array(cells[start..<min(start + 7, cells.count)])
            return slice + Array(repeating: nil, count: 7 - slice.count)
        }
    }
}

struct OverviewDailyCard: View {
    let days: [OverviewStore.DayCount]
    @AppStorage("overview.showOverdue") private var showOverdue = true
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        OverviewCard(title: "本周完成情况") {
            if days.isEmpty {
                EmptyChart()
            } else {
                Toggle("显示逾期", isOn: $showOverdue)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Chart {
                    ForEach(days) { day in
                        BarMark(x: .value("日期", OverviewDates.label(day.date, "EEE")), y: .value("数量", day.completed))
                            .foregroundStyle(by: .value("类型", "已完成"))
                            .cornerRadius(4)
                        if showOverdue {
                            BarMark(x: .value("日期", OverviewDates.label(day.date, "EEE")), y: .value("数量", day.overdue))
                                .foregroundStyle(by: .value("类型", "逾期"))
                                .cornerRadius(4)
                        }
                    }
                }
                .chartForegroundStyleScale(["已完成": c.completed, "逾期": c.overdue])
                .chartLegend(showOverdue ? .visible : .hidden)
                .frame(height: 180)
            }
        }
    }
}

struct OverviewMonthlyCard: View {
    let months: [OverviewStore.MonthCount]
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        OverviewCard(title: "每月趋势") {
            if months.isEmpty {
                EmptyChart()
            } else {
                Chart {
                    ForEach(months) { month in
                        let label = OverviewDates.label(month.monthStart, "M月")
                        LineMark(x: .value("月份", label), y: .value("数量", month.total))
                            .foregroundStyle(by: .value("类型", "任务总数"))
                            .symbol(.circle)
                        LineMark(x: .value("月份", label), y: .value("数量", month.completed))
                            .foregroundStyle(by: .value("类型", "已完成"))
                            .symbol(.circle)
                        LineMark(x: .value("月份", label), y: .value("数量", month.overdueCompleted))
                            .foregroundStyle(by: .value("类型", "逾期完成"))
                            .symbol(.circle)
                    }
                }
                .chartForegroundStyleScale(["任务总数": c.pending, "已完成": c.completed, "逾期完成": c.overdue])
                .frame(height: 200)
            }
        }
    }
}

struct OverviewWeeklyCard: View {
    let weeks: [OverviewStore.DayCount]
    @Environment(\.palette) private var t

    var body: some View {
        OverviewCard(title: "近 4 周完成") {
            if weeks.isEmpty {
                EmptyChart()
            } else {
                Chart(weeks.suffix(4)) { week in
                    BarMark(x: .value("周", OverviewDates.label(week.date, "M/d")), y: .value("完成", week.completed))
                        .foregroundStyle(t.primary.gradient)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text("\(week.completed)").font(.caption).foregroundStyle(t.onSurfaceVariant)
                        }
                }
                .frame(height: 160)
            }
        }
    }
}

// MARK: - 月度

struct OverviewMetricsCard: View {
    let review: OverviewStore.MonthReview
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        let month = review.monthStart.map { OverviewDates.label($0, "yyyy 年 M 月") }
        OverviewCard(title: "数据汇总", subtitle: month) {
            if review.monthStart == nil {
                EmptyChart(text: "上个月还没有数据")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    metric("任务总数", "\(review.totalTasks)", delta: review.totalTasks - review.previousTotalTasks, tint: c.pending)
                    metric("已完成", "\(review.completedTasks)", delta: review.completedTasks - review.previousCompletedTasks, tint: c.completed)
                    metric("完成率", Self.percent(review.completionRate),
                           deltaText: Self.pointDelta(review.completionRate - review.previousCompletionRate), tint: c.completed)
                    metric("逾期", "\(review.overdueTasks)", delta: review.overdueTasks - review.previousOverdueTasks, tint: c.overdue, lowerIsBetter: true)
                    metric("最活跃时段", review.mostActivePeriod?.title ?? "—", tint: t.tertiary)
                    metric("平均完成用时", review.averageCompletionMinutes.map(Self.minutes) ?? "—", tint: t.tertiary)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, delta: Int? = nil, deltaText: String? = nil,
                        tint: Color, lowerIsBetter: Bool = false) -> some View {
        let text = deltaText ?? delta.flatMap { $0 == 0 ? nil : ($0 > 0 ? "+\($0)" : "\($0)") }
        let improving = delta.map { lowerIsBetter ? $0 < 0 : $0 > 0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(t.onSurfaceVariant)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(tint)
            Text(text.map { "较前一月 \($0)" } ?? "\u{00A0}")
                .font(.caption2)
                .foregroundStyle(improving == false ? t.error : t.onSurfaceVariant)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func percent(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }

    static func pointDelta(_ diff: Double) -> String? {
        let points = Int((diff * 100).rounded())
        return points == 0 ? nil : (points > 0 ? "+\(points)%" : "\(points)%")
    }

    static func minutes(_ value: Int) -> String {
        if value < 60 { return "\(value) 分钟" }
        if value < 60 * 24 { return String(format: "%.1f 小时", Double(value) / 60) }
        return String(format: "%.1f 天", Double(value) / 1440)
    }
}

struct OverviewMonthMapCard: View {
    let review: OverviewStore.MonthReview
    @Environment(\.palette) private var t

    var body: some View {
        let title = review.monthStart.map { OverviewDates.label($0, "M月") + "活动分布" } ?? "活动分布"
        OverviewCard(title: title, subtitle: "每日完成数") {
            if review.daily.isEmpty {
                EmptyChart()
            } else {
                let weeks = OverviewHeatmapCard.weeks(review.daily)
                let peak = max(1, review.daily.map(\.completed).max() ?? 1)
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                            Text($0).font(.caption2).foregroundStyle(t.onSurfaceVariant).frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(weeks.indices, id: \.self) { w in
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { d in
                                cell(weeks[w][d], peak: peak)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: OverviewStore.DayCount?, peak: Int) -> some View {
        if let day {
            let fill = day.completed == 0 ? t.onSurface.opacity(0.06) : t.primary.opacity(0.2 + 0.7 * Double(day.completed) / Double(peak))
            Text(OverviewDates.label(day.date, "d"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(day.completed * 2 > peak ? .white : t.onSurface)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("完成 \(day.completed)" + (day.overdue > 0 ? "，逾期 \(day.overdue)" : ""))
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 30)
        }
    }
}

struct OverviewTitlesCard: View {
    let review: OverviewStore.MonthReview
    @Environment(\.palette) private var t

    var body: some View {
        OverviewCard(title: "上月完成的任务", subtitle: "\(review.completedTitles.count) 个") {
            FlowLayout(spacing: 6) {
                ForEach(Array(review.completedTitles.enumerated()), id: \.offset) { _, title in
                    Text(verbatim: title)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(OverviewColors(t: t).completed.opacity(0.14), in: Capsule())
                }
            }
        }
    }
}
