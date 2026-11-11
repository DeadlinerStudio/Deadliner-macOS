import Charts
import SwiftUI

/// 桌面概览入口；复用下方统计卡片，导航与区间查询由工作台组织。
struct OverviewView: View {
    let store: OverviewStore
    var body: some View { OverviewWorkbench(store: store) }
}

enum OverviewSection: String, CaseIterable, Identifiable {
    case stats, trends
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stats: "总览"
        case .trends: "趋势"
        }
    }
}

/// 总览的范围：`all`、`custom`（自定义日期范围）或某个月的第一天（`yyyy-MM-01`）。
enum OverviewRange {
    static let all = "all"
    static let custom = "custom"

    /// 相邻的月份；`offset` 为 -1 / 1。超过本月时返回 nil。
    static func month(_ monthStart: String, offset: Int, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = OverviewDates.date(monthStart),
              let moved = calendar.date(byAdding: .month, value: offset, to: date) else { return nil }
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        guard moved <= current else { return nil }
        return DateRange.isoString(moved)
    }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case week, month, year, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: "周"
        case .month: "月"
        case .year: "年"
        case .custom: "自定义"
        }
    }
}

/// 页面主体，便于截图测试。
struct OverviewContent: View {
    let store: OverviewStore
    let section: OverviewSection
    @Binding var range: String
    @Binding var trend: TrendRange
    var layout: CardLayout = .single
    var customRange: DateRange = .fallback
    var onEditRange: () -> Void = {}
    @Environment(\.palette) private var t

    /// 单列时卡片纵向排列；双列、三列时成对的卡片并排且等高。
    private var columns: Int { layout == .single ? 1 : 2 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: MiuixCard.gap) {
                rangeBar
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(t.error)
                } else {
                    switch section {
                    case .stats: statsBody
                    case .trends: trendsBody
                    }
                }
            }
            .readableWidth(layout.maxContentWidth)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .overlay {
            if store.isLoading { ProgressView() }
        }
    }

    @ViewBuilder
    private var rangeBar: some View {
        HStack(spacing: 8) {
            switch section {
            case .stats:
                let isMonth = range != OverviewRange.all && range != OverviewRange.custom
                if isMonth {
                    Button { if let previous = OverviewRange.month(range, offset: -1) { range = previous } } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help("上个月（⌘←）")
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                }
                Picker("范围", selection: $range) {
                    Text("全部时间").tag(OverviewRange.all)
                    Divider()
                    ForEach(monthOptions, id: \.self) { month in
                        Text(OverviewDates.label(month, "yyyy 年 M 月")).tag(month)
                    }
                    Divider()
                    Text("自定义…").tag(OverviewRange.custom)
                }
                .pickerStyle(.menu)
                .fixedSize()
                if isMonth {
                    let next = OverviewRange.month(range, offset: 1)
                    Button { if let next { range = next } } label: { Image(systemName: "chevron.right") }
                        .disabled(next == nil)
                        .help("下个月（⌘→）")
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                }
                if range == OverviewRange.custom { rangeButton }
            case .trends:
                Picker("范围", selection: $trend) {
                    ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                if trend == .custom { rangeButton }
            }
            Spacer()
        }
        .labelsHidden()
    }

    /// 显示当前自定义范围，点击修改。
    private var rangeButton: some View {
        Button(action: onEditRange) {
            Label(customRange.label, systemImage: "calendar")
        }
        .help("修改时间范围")
    }

    /// 菜单中的月份：Core 给出的近 12 个月，加上当前选中的月份（翻到更早时）。
    private var monthOptions: [String] {
        var months = store.monthly.reversed().map(\.monthStart)
        if range != OverviewRange.all && range != OverviewRange.custom && !months.contains(range) { months.append(range) }
        return months.sorted(by: >)
    }

    @ViewBuilder
    private var statsBody: some View {
        if range == OverviewRange.all {
            OverviewTodayCard(today: store.today, focusSeconds: store.focus.todaySeconds)
            OverviewRow(columns: columns) {
                OverviewPeriodCard(periods: store.periods)
                OverviewHistoryCard(history: store.history, title: "历史统计", subtitle: "全部时间")
            }
        } else if let month = store.month, month.review.monthStart == range {
            OverviewMetricsCard(review: month.review, headline: samePeriodText(month))
            OverviewRow(columns: columns) {
                OverviewMonthMapCard(review: month.review, focus: store.focusMonth)
                OverviewHistoryCard(history: month.distribution, title: "状态分布", subtitle: "完成按完成日期，其余按截止日期")
            }
            if let focus = store.focusMonth { OverviewFocusInvestmentCard(focus: focus) }
            if !month.review.completedTitles.isEmpty {
                OverviewTitlesCard(review: month.review)
            }
        } else if range == OverviewRange.custom {
            customStatsBody
        } else if let error = store.monthError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(t.error)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    /// 自定义范围的总览：与「某个月」相同的内容，并补上完成时间分布。
    @ViewBuilder
    private var customStatsBody: some View {
        if let detail = currentRange {
            if detail.extendsIntoFuture { futureNote(detail) }
            OverviewMetricsCard(review: detail.review, subtitle: customRange.label, comparison: "较前一时段",
                                emptyText: "这段时间没有任务")
            OverviewRow(columns: columns) {
                OverviewPeriodCard(periods: detail.periods)
                OverviewHistoryCard(history: detail.distribution, title: "状态分布", subtitle: "截止日期在范围内的任务")
            }
            // 两个月以内用日历（可以看到具体日期），更长的范围用热力图。
            if let focus = store.focusCustom { OverviewFocusInvestmentCard(focus: focus) }
            if detail.review.daily.count <= 62 {
                OverviewMonthMapCard(review: detail.review, focus: store.focusCustom)
            } else {
                OverviewHeatmapCard(days: detail.review.daily, title: "活动分布")
            }
            if !detail.review.completedTitles.isEmpty {
                OverviewTitlesCard(review: detail.review, title: "范围内完成的任务")
            }
        } else if let error = store.rangeError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(t.error)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    /// 当前月份显示「本月至今完成 N 项 · 较上月同期 ↑ x」（与 Android 一致）；已结束的月份不显示。
    private func samePeriodText(_ month: OverviewStore.MonthDetail) -> String? {
        guard month.review.monthStart == DateRange.isoString(Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()),
              let (current, previous) = OverviewStore.samePeriod(current: month.review.daily, previous: store.previousMonthDaily,
                                                                 today: Date()) else { return nil }
        let change = current - previous
        let comparison = previous == 0 ? (current > 0 ? "较上月同期 +\(current) 项" : "与上月同期持平")
            : change == 0 ? "与上月同期持平" : "较上月同期 \(change > 0 ? "↑" : "↓") \(abs(change)) 项"
        return "本月至今完成 \(current) 项 · \(comparison)"
    }

    /// 与当前选择一致的范围数据（切换范围后、新数据到达前不显示旧数据）。
    private var currentRange: OverviewStore.RangeDetail? {
        guard let detail = store.range, detail.start == DateRange.isoString(customRange.start),
              detail.endExclusive == DateRange.isoString(customRange.endExclusive()) else { return nil }
        return detail
    }

    private func futureNote(_ detail: OverviewStore.RangeDetail) -> some View {
        Label("完成情况统计到今天（\(OverviewDates.label(detail.asOf, "M月d日"))）；之后的日期只计入到期的任务。",
              systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(t.onSurfaceVariant)
    }

    @ViewBuilder
    private var trendsBody: some View {
        let c = OverviewColors(t: t)
        switch trend {
        case .week:
            let completed = store.daily.map(\.completed).reduce(0, +)
            OverviewSummaryCard(items: [
                ("近 7 天完成", "\(completed)", c.completed),
                ("近 7 天逾期", "\(store.daily.map(\.overdue).reduce(0, +))", c.overdue),
                ("日均完成", Self.average(completed, store.daily.count), c.pending),
            ])
            OverviewDailyCard(days: store.daily)
            OverviewFocusBarsCard(points: Array(store.focus.daily.suffix(7)), subtitle: "近 7 天", unit: .day)
        case .month:
            let days = Array(store.contribution.suffix(30))
            let completed = days.map(\.completed).reduce(0, +)
            OverviewSummaryCard(items: [
                ("近 30 天完成", "\(completed)", c.completed),
                ("有完成的天数", "\(days.filter { $0.completed > 0 }.count)", t.tertiary),
                ("日均完成", Self.average(completed, days.count), c.pending),
            ])
            OverviewRangeDailyCard(days: days)
            OverviewFocusBarsCard(points: store.focusLast30?.daily ?? [], subtitle: "近 30 天", unit: .day)
        case .year:
            OverviewSummaryCard(items: [
                ("近 12 个月任务", "\(store.monthly.map(\.total).reduce(0, +))", c.pending),
                ("已完成", "\(store.monthly.map(\.completed).reduce(0, +))", c.completed),
                ("逾期完成", "\(store.monthly.map(\.overdueCompleted).reduce(0, +))", c.overdue),
            ])
            OverviewMonthlyCard(months: store.monthly)
            OverviewFocusBarsCard(points: Array(store.focus.monthly.suffix(12)), subtitle: "近 12 个月", unit: .month)
        case .custom:
            if let detail = currentRange {
                let elapsed = detail.elapsedDaily
                let completed = elapsed.map(\.completed).reduce(0, +)
                if detail.extendsIntoFuture { futureNote(detail) }
                OverviewSummaryCard(items: [
                    ("完成", "\(completed)", c.completed),
                    ("逾期", "\(elapsed.map(\.overdue).reduce(0, +))", c.overdue),
                    ("日均完成", Self.average(completed, elapsed.count), c.pending),
                ])
                OverviewRangeDailyCard(days: detail.review.daily, subtitle: customRange.label)
                OverviewFocusBarsCard(points: store.focusCustom?.daily ?? [], subtitle: customRange.label, unit: .day)
            } else if let error = store.rangeError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(t.error)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        OverviewRow(columns: columns) {
            OverviewHeatmapCard(days: store.contribution)
            OverviewWeeklyCard(weeks: store.weekly)
        }
    }

    static func average(_ total: Int, _ days: Int) -> String {
        guard days > 0 else { return "0" }
        return String(format: "%.1f", Double(total) / Double(days))
    }
}

/// 一行卡片：多列时并排且等高，单列时纵向排列。
struct OverviewRow<Content: View>: View {
    let columns: Int
    @ViewBuilder var content: Content

    var body: some View {
        if columns > 1 {
            HStack(alignment: .top, spacing: MiuixCard.gap) { content }
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: MiuixCard.gap) { content }
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
    /// 专注统一用青绿色，与菜单栏和专注页一致。
    var focus: Color { Color(hex: 0x14B8A6) }
}

enum OverviewDates {
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ raw: String) -> Date? {
        iso.timeZone = .current
        return iso.date(from: raw)
    }

    /// 悬停提示：日期、当日完成任务数，换行后当日专注时长。
    static func dayTooltip(_ day: OverviewStore.DayCount, focusSeconds: Int) -> String {
        "\(label(day.date, "M月d日 EEE"))\n完成 \(day.completed) 项任务\n专注 \(focusSeconds > 0 ? FocusTexts.duration(focusSeconds) : "0 分钟")"
    }

    static func label(_ raw: String, _ format: String) -> String {
        guard let date = date(raw) else { return raw }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = OverviewPeriod.calendar
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(OverviewCardBackground())
    }
}

struct OverviewCardBackground: ViewModifier {
    @Environment(\.palette) private var t
    func body(content: Content) -> some View {
        content.background(t.groupBg, in: RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
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
    var focusSeconds = 0
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        OverviewCard(title: "今日概况") {
            HStack {
                BigNumber(title: "今日完成", value: "\(today.completed)", tint: c.completed)
                BigNumber(title: "待完成", value: "\(today.pending)", tint: c.pending)
                BigNumber(title: "今日逾期", value: "\(today.overdue)", tint: c.overdue)
                BigNumber(title: "已放弃", value: "\(today.abandoned)", tint: c.abandoned)
                BigNumber(title: "今日专注", value: FocusTexts.compact(focusSeconds), tint: c.focus)
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
    var title = "历史统计"
    var subtitle: String?
    /// 已完成中超前、提前完成各多少（Mac 端推算）；有值时环图和图例里把它们从「已完成」中分出来。
    var completedTiming: [CompletionTiming: Int]?
    @Environment(\.palette) private var t

    private struct Slice: Identifiable {
        let id: String
        let count: Int
        let color: Color
        var indented = false
    }

    var body: some View {
        let c = OverviewColors(t: t)
        let ahead = min(history.completed, completedTiming?[.ahead] ?? 0)
        let early = min(history.completed - ahead, completedTiming?[.early] ?? 0)
        let splits = completedTiming != nil && ahead + early > 0
        // 环图：已完成拆成超前、提前与其余；图例：「已完成」下面缩进列出超前、提前。
        let sectors: [Slice] = (splits ? [
            Slice(id: "超前完成", count: ahead, color: IndicatorStatus.completedAhead.solid(t)),
            Slice(id: "提前完成", count: early, color: IndicatorStatus.completedEarly.solid(t)),
            Slice(id: "已完成", count: history.completed - ahead - early, color: c.completed),
        ] : [Slice(id: "已完成", count: history.completed, color: c.completed)]) + [
            Slice(id: "未完成", count: history.onTime, color: c.pending),
            Slice(id: "逾期", count: history.overdue, color: c.overdue),
            Slice(id: "已放弃", count: history.abandoned, color: c.abandoned),
        ]
        let legend: [Slice] = [Slice(id: "已完成", count: history.completed, color: c.completed)]
            + (splits ? [
                Slice(id: "超前完成", count: ahead, color: IndicatorStatus.completedAhead.solid(t), indented: true),
                Slice(id: "提前完成", count: early, color: IndicatorStatus.completedEarly.solid(t), indented: true),
            ] : [])
            + sectors.filter { !["已完成", "超前完成", "提前完成"].contains($0.id) }
        OverviewCard(title: title, subtitle: subtitle) {
            if history.total == 0 {
                EmptyChart()
            } else {
                HStack(spacing: 24) {
                    Chart(sectors) { slice in
                        SectorMark(angle: .value("数量", slice.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(slice.color)
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
                        ForEach(legend) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: slice.indented ? 7 : 9, height: slice.indented ? 7 : 9)
                                Text(slice.id).font(slice.indented ? .caption : .callout)
                                    .foregroundStyle(slice.indented ? t.onSurfaceVariant : t.onSurface)
                                Spacer(minLength: 12)
                                Text("\(slice.count)").font((slice.indented ? Font.caption : .callout).monospacedDigit())
                                    .foregroundStyle(t.onSurfaceVariant)
                            }
                            .padding(.leading, slice.indented ? 16 : 0)
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
    var title = "活跃热力图"
    /// 每天的专注秒数（键为 `yyyy-MM-dd`），用于悬停提示。
    var focus: [String: Int] = [:]
    @State private var width: CGFloat = 400
    @Environment(\.palette) private var t

    /// 每月第一周的列上方显示月份。
    static func monthLabel(_ weeks: [[OverviewStore.DayCount?]], _ index: Int) -> String {
        guard let first = weeks[index].compactMap({ $0 }).first(where: { $0.date.hasSuffix("-01") })
                ?? (index == 0 ? weeks[index].compactMap({ $0 }).first : nil) else { return "" }
        return OverviewDates.label(first.date, "M月")
    }

    var body: some View {
        OverviewCard(title: title, subtitle: days.isEmpty ? nil : "\(days.count) 天内") {
            if days.isEmpty {
                EmptyChart()
            } else {
                let weeks = Self.weeks(days)
                let peak = max(1, days.map(\.completed).max() ?? 1)
                // 方格大小随卡片宽度变化，铺满整行（8～22pt）。
                let gap: CGFloat = 3
                let labelWidth: CGFloat = 18
                let cell = min(22, max(8, (width - labelWidth - gap * CGFloat(weeks.count)) / CGFloat(max(1, weeks.count))))
                ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: gap) {
                    HStack(spacing: gap) {
                        Color.clear.frame(width: labelWidth, height: 12)
                        ForEach(weeks.indices, id: \.self) { w in
                            Text(Self.monthLabel(weeks, w))
                                .font(.system(size: 9))
                                .foregroundStyle(t.onSurfaceVariant)
                                .fixedSize()
                                .frame(width: cell, height: 12, alignment: .leading)
                        }
                    }
                    ForEach(0..<7, id: \.self) { d in
                        HStack(spacing: gap) {
                            Text(d % 2 == 0 ? ["一", "", "三", "", "五", "", "日"][d] : "")
                                .font(.system(size: 9))
                                .foregroundStyle(t.onSurfaceVariant)
                                .frame(width: labelWidth, height: cell, alignment: .leading)
                            ForEach(weeks.indices, id: \.self) { w in
                                let day = weeks[w][d]
                                RoundedRectangle(cornerRadius: cell / 4, style: .continuous)
                                    .fill(color(day?.completed, peak: peak))
                                    .frame(width: cell, height: cell)
                                    .help(day.map { OverviewDates.dayTooltip($0, focusSeconds: focus[$0.date] ?? 0) } ?? "")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { width = proxy.size.width }
                        .onChange(of: proxy.size.width) { width = proxy.size.width }
                })
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
        OverviewCard(title: "每日完成", subtitle: "近 7 天") {
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
                // 坐标范围始终包含逾期，开关「显示逾期」时坐标系不缩放。
                .chartYScale(domain: 0...Double(max(1, days.map { $0.completed + $0.overdue }.max() ?? 1)))
                .chartLegend(.visible)
                .frame(height: 200)
            }
        }
    }
}

struct OverviewSummaryCard: View {
    let items: [(String, String, Color)]

    var body: some View {
        HStack {
            ForEach(items, id: \.0) { item in
                BigNumber(title: item.0, value: item.1, tint: item.2)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .modifier(OverviewCardBackground())
    }
}

/// 近 30 天每日完成（Core 热力图数据的最后 30 天）。
struct OverviewRangeDailyCard: View {
    let days: [OverviewStore.DayCount]
    var subtitle = "近 30 天"
    @Environment(\.palette) private var t

    var body: some View {
        // 横轴最多标约 6 个日期，范围很长时也不会挤在一起。
        let stride = max(1, Int((Double(days.count) / 6).rounded(.up)))
        OverviewCard(title: "每日完成", subtitle: subtitle) {
            if days.allSatisfy({ $0.completed == 0 }) {
                EmptyChart()
            } else {
                Chart(days) { day in
                    BarMark(x: .value("日期", OverviewDates.date(day.date) ?? Date(), unit: .day), y: .value("完成", day.completed))
                        .foregroundStyle(OverviewColors(t: t).completed.gradient)
                        .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: stride)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(verbatim: "\(Calendar.current.component(.month, from: date))/\(Calendar.current.component(.day, from: date))")
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
    }
}

struct OverviewMonthlyCard: View {
    let months: [OverviewStore.MonthCount]
    /// 每月的超前、提前完成数（Mac 端推算，键为月初）。
    var timings: [String: [CompletionTiming: Int]] = [:]
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        OverviewCard(title: "每月趋势", subtitle: "近 12 个月") {
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
                        LineMark(x: .value("月份", label), y: .value("数量", timings[month.monthStart]?[.ahead] ?? 0))
                            .foregroundStyle(by: .value("类型", "超前完成"))
                            .symbol(.circle)
                        LineMark(x: .value("月份", label), y: .value("数量", timings[month.monthStart]?[.early] ?? 0))
                            .foregroundStyle(by: .value("类型", "提前完成"))
                            .symbol(.circle)
                    }
                }
                .chartForegroundStyleScale(["任务总数": c.pending, "已完成": c.completed, "逾期完成": c.overdue,
                                            "超前完成": IndicatorStatus.completedAhead.solid(t),
                                            "提前完成": IndicatorStatus.completedEarly.solid(t)])
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
                    BarMark(x: .value("周", OverviewDates.label(week.date, "M/d")), y: .value("完成", week.completed),
                            width: .ratio(0.38))
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
    /// 默认显示月份；自定义范围时显示范围。
    var subtitle: String?
    /// 对比的说法：某个月为「较前一月」，自定义范围为「较前一时段」（等长）。
    var comparison = "较前一月"
    var emptyText = "这个月没有任务"
    /// 卡片顶部的一行说明（例如「较上月同期」）。
    var headline: String?
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        let month = subtitle ?? review.monthStart.map { OverviewDates.label($0, "yyyy 年 M 月") }
        OverviewCard(title: "数据汇总", subtitle: month) {
            if let headline {
                Text(headline).font(.callout.weight(.medium)).foregroundStyle(c.completed)
            }
            if review.totalTasks == 0 && review.completedTasks == 0 {
                EmptyChart(text: emptyText)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
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
            Text(text.map { "\(comparison) \($0)" } ?? "\u{00A0}")
                .font(.caption2)
                .foregroundStyle(improving == false ? t.error : t.onSurfaceVariant)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Core 的完成率是百分数（0～100）。
    static func percent(_ rate: Double) -> String { "\(Int(rate.rounded()))%" }

    static func pointDelta(_ diff: Double) -> String? {
        let points = Int(diff.rounded())
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
    /// 有专注的日子在格子右上角标一个点；点日期显示当天明细。
    var focus: OverviewStore.FocusRange?
    @State private var selectedDay: String?
    @Environment(\.palette) private var t

    var body: some View {
        let title = review.monthStart.map { OverviewDates.label($0, "M月") + "活动分布" } ?? "活动分布"
        OverviewCard(title: title, subtitle: focus == nil ? "每日完成数" : "每日完成数 · 点为有专注") {
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
            let focusSeconds = focus?.seconds(on: day.date) ?? 0
            Text(OverviewDates.label(day.date, day.date.hasSuffix("-01") ? "M/d" : "d"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(day.completed * 2 > peak ? .white : t.onSurface)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if focusSeconds > 0 {
                        Circle().fill(OverviewColors(t: t).focus).frame(width: 5, height: 5).padding(4)
                    }
                }
                .overlay {
                    if selectedDay == day.date {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.onSurface.opacity(0.5), lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedDay = day.date }
                .popover(isPresented: Binding(get: { selectedDay == day.date }, set: { if !$0 { selectedDay = nil } })) {
                    dayDetail(day, focusSeconds: focusSeconds)
                }
                .help("完成 \(day.completed)" + (day.overdue > 0 ? "，逾期 \(day.overdue)" : "") +
                      (focusSeconds > 0 ? "，专注 \(FocusTexts.duration(focusSeconds))" : ""))
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 30)
        }
    }

    /// 当天明细（与 Android 点击日期的弹窗一致）。
    private func dayDetail(_ day: OverviewStore.DayCount, focusSeconds: Int) -> some View {
        let c = OverviewColors(t: t)
        return VStack(alignment: .leading, spacing: 8) {
            Text(OverviewDates.label(day.date, "M月d日 EEEE")).font(.headline)
            Label("完成 \(day.completed) 项", systemImage: "checkmark.circle").foregroundStyle(c.completed)
            if day.overdue > 0 { Label("逾期 \(day.overdue) 项", systemImage: "exclamationmark.circle").foregroundStyle(c.overdue) }
            Label(focusSeconds > 0 ? "专注 \(FocusTexts.duration(focusSeconds))" : "没有专注", systemImage: "timer")
                .foregroundStyle(focusSeconds > 0 ? c.focus : t.onSurfaceVariant)
        }
        .font(.callout)
        .padding(14)
        .frame(minWidth: 180, alignment: .leading)
    }
}

/// 专注时长柱状图（每日或每月）。
struct OverviewFocusBarsCard: View {
    enum Unit { case day, month }
    let points: [OverviewStore.FocusPoint]
    var subtitle: String
    var unit: Unit = .day
    @State private var hovered: OverviewStore.FocusPoint?
    @Environment(\.palette) private var t

    var body: some View {
        let total = points.map(\.seconds).reduce(0, +)
        let average = FocusTexts.dailyAverage(points, byMonth: unit == .month)
        OverviewCard(title: "专注时长", subtitle: total > 0
                     ? "\(subtitle) · 合计 \(FocusTexts.duration(total)) · 日均 \(FocusTexts.duration(average))" : subtitle) {
            if total == 0 {
                EmptyChart(text: "这段时间没有专注")
            } else {
                let stride = max(1, Int((Double(points.count) / 6).rounded(.up)))
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("日期", OverviewDates.date(point.start) ?? Date(), unit: unit == .day ? .day : .month),
                                y: .value("分钟", Double(point.seconds) / 60))
                            .foregroundStyle(OverviewColors(t: t).focus.gradient)
                            .opacity(hovered == nil || hovered == point ? 1 : 0.45)
                            .cornerRadius(3)
                    }
                    // 鼠标悬停的柱子：上方显示具体时长。
                    if let hovered, let date = OverviewDates.date(hovered.start) {
                        RuleMark(x: .value("日期", date, unit: unit == .day ? .day : .month))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 1) {
                                    Text(OverviewDates.label(hovered.start, unit == .day ? "M月d日" : "yyyy年M月"))
                                        .font(.caption2).foregroundStyle(t.onSurfaceVariant)
                                    Text(FocusTexts.duration(hovered.seconds)).font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(t.groupBg, in: RoundedRectangle(cornerRadius: 7))
                                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                guard case .active(let location) = phase, let frame = proxy.plotFrame,
                                      let date: Date = proxy.value(atX: location.x - geometry[frame].origin.x) else {
                                    hovered = nil
                                    return
                                }
                                let calendar = Calendar.current
                                hovered = points.first { point in
                                    guard let start = OverviewDates.date(point.start) else { return false }
                                    return unit == .day ? calendar.isDate(start, inSameDayAs: date)
                                        : calendar.isDate(start, equalTo: date, toGranularity: .month)
                                }
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let minutes = value.as(Double.self) { Text(FocusTexts.compact(Int(minutes * 60))) } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: unit == .day ? .day : .month, count: stride)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                let calendar = Calendar.current
                                Text(verbatim: unit == .day
                                     ? "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
                                     : "\(calendar.component(.month, from: date))月")
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
    }
}

/// 时间投入：专注总时长、次数、活跃天数，以及按分类的分布（与 Android 月度复盘的「时间投入」一致）。
struct OverviewFocusInvestmentCard: View {
    let focus: OverviewStore.FocusRange
    @Environment(\.palette) private var t

    var body: some View {
        let c = OverviewColors(t: t)
        OverviewCard(title: "时间投入", subtitle: "专注") {
            if focus.totalSeconds == 0 {
                EmptyChart(text: "这段时间没有专注")
            } else {
                HStack {
                    BigNumber(title: "专注时长", value: FocusTexts.compact(focus.totalSeconds), tint: c.focus)
                    BigNumber(title: "专注次数", value: "\(focus.sessions)", tint: c.focus)
                    BigNumber(title: "有专注的天数", value: "\(focus.activeDays)", tint: c.focus)
                    BigNumber(title: "日均专注", value: FocusTexts.compact(FocusTexts.dailyAverage(focus.daily)), tint: c.focus)
                }
                let peak = max(1, focus.categories.first?.seconds ?? 1)
                VStack(spacing: 10) {
                    ForEach(Array(focus.categories.prefix(6).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 12) {
                            Text(verbatim: item.title).font(.callout).lineLimit(1).frame(width: 90, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(t.onSurface.opacity(0.06))
                                    Capsule().fill(c.focus.gradient)
                                        .frame(width: max(8, proxy.size.width * Double(item.seconds) / Double(peak)))
                                }
                            }
                            .frame(height: 10)
                            Text(FocusTexts.compact(item.seconds)).font(.callout.monospacedDigit())
                                .foregroundStyle(t.onSurfaceVariant).frame(minWidth: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

struct OverviewTitlesCard: View {
    let review: OverviewStore.MonthReview
    var title: String?
    @Environment(\.palette) private var t

    var body: some View {
        let month = review.monthStart.map { OverviewDates.label($0, "M月") } ?? "所选区间"
        OverviewCard(title: title ?? "\(month)完成的任务", subtitle: "\(review.completedTitles.count) 个") {
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

/// 完成时机：所选月份 / 区间内完成的任务里，超前、提前、按时、逾期完成各多少。
/// 由开始时间、截止时间和完成时间在 Mac 上推算（手机上不显示），颜色与任务卡片相同，可在设置中自定义。
struct OverviewCompletionTimingCard: View {
    let counts: [CompletionTiming: Int]
    var subtitle: String?
    @Environment(\.palette) private var t

    var body: some View {
        let total = CompletionTiming.allCases.reduce(0) { $0 + (counts[$1] ?? 0) }
        OverviewCard(title: "完成时机", subtitle: subtitle ?? "按开始、截止与完成时间推算") {
            if total == 0 {
                EmptyChart(text: "这段时间没有可比较的已完成任务")
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(CompletionTiming.allCases) { timing in
                            let count = counts[timing] ?? 0
                            if count > 0 {
                                timing.status.solid(t)
                                    .frame(width: max(4, proxy.size.width * CGFloat(count) / CGFloat(total) - 2))
                            }
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                ForEach(CompletionTiming.allCases) { timing in
                    HStack {
                        Circle().fill(timing.status.solid(t)).frame(width: 9, height: 9)
                        Text(timing.title)
                        Spacer()
                        Text("\(counts[timing] ?? 0)").monospacedDigit().fontWeight(.semibold)
                        Text(Self.percent(counts[timing] ?? 0, of: total))
                            .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                    .font(.callout)
                }
                Text("超前：开始前就完成；提前：比截止日早至少一天。没有截止时间的任务只计超前完成。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func percent(_ value: Int, of total: Int) -> String {
        total > 0 ? "\(Int((Double(value) / Double(total) * 100).rounded()))%" : "–"
    }
}

/// 总览「近期趋势」：最近 7 天每天完成数，超前、提前完成在柱内分段显示。
struct OverviewRecentTimingChart: View {
    let days: [OverviewStore.DayCount]
    var timings: [String: [CompletionTiming: Int]] = [:]
    @Environment(\.palette) private var t

    private struct Segment: Identifiable {
        let date: String
        let kind: String
        let count: Int
        var id: String { date + kind }
    }

    var body: some View {
        let segments = days.flatMap { day -> [Segment] in
            let ahead = min(day.completed, timings[day.date]?[.ahead] ?? 0)
            let early = min(day.completed - ahead, timings[day.date]?[.early] ?? 0)
            return [Segment(date: day.date, kind: "已完成", count: day.completed - ahead - early),
                    Segment(date: day.date, kind: "提前完成", count: early),
                    Segment(date: day.date, kind: "超前完成", count: ahead)]
        }
        Chart(segments) { segment in
            BarMark(x: .value("日期", OverviewDates.label(segment.date, "E")), y: .value("完成", segment.count))
                .foregroundStyle(by: .value("类型", segment.kind))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(["已完成": OverviewColors(t: t).completed,
                                    "提前完成": IndicatorStatus.completedEarly.solid(t),
                                    "超前完成": IndicatorStatus.completedAhead.solid(t)])
        .chartLegend(position: .bottom, spacing: 6)
        .frame(height: 120)
    }
}
