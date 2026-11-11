import SwiftUI
import Charts

enum OverviewTab: String, CaseIterable, Identifiable {
    case dashboard = "总览", tasks = "任务统计", trends = "趋势分析", review = "月度复盘"
    var id: String { rawValue }
}

struct OverviewWorkbench: View {
    let store: OverviewStore
    @AppStorage("overview.desktop.tab") private var tab = OverviewTab.dashboard
    @State private var selectedMonth = OverviewPeriod.month()
    @State private var scope = "所选月"
    @AppStorage("overview.desktop.taskOrder") private var taskOrderRaw = "今日概况,完成时间分布,历史统计"
    @State private var start = OverviewPeriod.month()
    @State private var end = Date()
    @State private var draftStart = OverviewPeriod.month()
    @State private var draftEnd = Date()
    @State private var rangeError: String?
    @State private var insight = MonthlyInsightStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.palette) private var t

    var body: some View {
        GeometryReader { proxy in
            let columns = proxy.size.width >= 1200 ? 3 : proxy.size.width >= 850 ? 2 : 1
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch tab {
                        case .dashboard: dashboard(columns: columns)
                        case .tasks: tasks(columns: columns)
                        case .trends: OverviewTrendWorkspace(store: store, columns: columns)
                        case .review: OverviewReviewWorkspace(store: store, insight: insight, columns: columns)
                        }
                    }
                    .frame(maxWidth: 1800)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }.id(tab)
            }
        }
        .topAtmosphere(t.primary)
        .background(t.pageBg)
        .navigationTitle("概览")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("概览分区", selection: $tab) {
                    ForEach(OverviewTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem {
                if store.isLoading { ProgressView().controlSize(.small) }
            }
            ToolbarItem { Button { refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }.help("刷新所有概览数据") }
        }
        .onAppear {
            store.loadMonth(OverviewPeriod.key(selectedMonth))
            refresh()
        }
        .onChange(of: scenePhase) { if scenePhase == .active { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refresh() }
        .onChange(of: store.lastMonth) { loadInsight() }
        .onChange(of: store.isLoading) { if !store.isLoading { loadInsight() } }
    }

    private var monthControls: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(OverviewDates.label(OverviewPeriod.key(selectedMonth), "yyyy 年 M 月")).font(.title2.bold())
                Text(selectedMonth == OverviewPeriod.month() ? "本月进行中" : "历史月份 · 按当前任务状态统计")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }.help("上个月（⌘←）")
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(OverviewPeriod.calendar.component(.year, from: selectedMonth) <= 1900)
            Button("本月") { selectedMonth = OverviewPeriod.month(); selectMonth() }
            Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }.help("下个月（⌘→）")
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(selectedMonth >= OverviewPeriod.month())
        }
    }

    @ViewBuilder private func dashboard(columns: Int) -> some View {
        monthControls
        if let error = store.monthError {
            OverviewError(message: error) { store.loadMonth(OverviewPeriod.key(selectedMonth)) }
        } else if let detail = store.month, !store.monthLoading {
            if columns == 3 {
                HStack(alignment: .top, spacing: 18) {
                    OverviewActivityCalendar(review: detail.review, focus: monthFocus).frame(maxWidth: .infinity)
                    VStack(spacing: 18) { result(detail); preview }.frame(maxWidth: .infinity)
                    reviewPreview.frame(maxWidth: .infinity)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: columns), alignment: .leading, spacing: 18) {
                    OverviewActivityCalendar(review: detail.review, focus: monthFocus)
                    result(detail)
                    preview
                    reviewPreview
                }
            }
            if let focus = store.focusMonth { OverviewFocusInvestmentCard(focus: focus) }
            OverviewCompletionTimingCard(counts: store.monthTiming, subtitle: "\(Self.monthPhrase(selectedMonth))内完成的任务")
        } else { ProgressView("加载月份…").frame(maxWidth: .infinity, minHeight: 240) }
    }

    private func result(_ detail: OverviewStore.MonthDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(detail.review.daily.reduce(0) { $0 + $1.completed }) 项").font(.largeTitle.bold()).monospacedDigit()
                    if let previous = store.previousMonth {
                        Text(OverviewPeriod.comparison(current: detail.review.daily.map(\.completed), previous: previous.daily.map(\.completed),
                            day: selectedMonth == OverviewPeriod.month() ? OverviewPeriod.calendar.component(.day, from: Date()) : detail.review.daily.count))
                            .font(.callout).foregroundStyle(comparisonColor(detail.review, previous))
                    } else if let error = store.comparisonError {
                        OverviewError(message: "同期比较：" + error) { selectMonth() }
                    } else { ProgressView("加载同期数据…").controlSize(.small) }
                }
                Spacer()
                Button("任务统计") { tab = .tasks; scope = "所选月"; loadRange() }
            }
            OverviewHistoryCard(history: detail.distribution, title: "所选月成果", subtitle: "完成活动与当前状态",
                                completedTiming: store.monthTiming)
        }
        .padding(18).background(t.groupBg, in: RoundedRectangle(cornerRadius: MiuixRadius.card))
    }

    private func comparisonColor(_ current: OverviewStore.MonthReview, _ previous: OverviewStore.MonthReview) -> Color {
        let day = selectedMonth == OverviewPeriod.month() ? OverviewPeriod.calendar.component(.day, from: Date()) : current.daily.count
        let delta = current.daily.prefix(day).reduce(0) { $0 + $1.completed } - previous.daily.prefix(day).reduce(0) { $0 + $1.completed }
        return delta > 0 ? .green : delta < 0 ? .red : .secondary
    }

    private var preview: some View {
        OverviewCard(title: "近期趋势", subtitle: "最近 7 天") {
            if let error = store.errorMessage { OverviewError(message: error, retry: refresh) }
            else {
                OverviewRecentTimingChart(days: store.daily, timings: store.dayTimings)
                Button("展开趋势分析") { tab = .trends }
            }
        }
    }

    private var reviewPreview: some View {
        OverviewCard(title: "月度复盘", subtitle: store.lastMonth.monthStart.map { OverviewDates.label($0, "yyyy 年 M 月") }) {
            MonthlyInsightContent(store: insight, review: store.lastMonth)
            Button("查看完整复盘与分享") { tab = .review }
        }
    }

    @ViewBuilder private func tasks(columns: Int) -> some View {
        HStack {
            Text("任务统计").font(.title2.bold())
            Spacer()
            Picker("范围", selection: $scope) {
                ForEach(["所选月", "近30天", "本年", "自定义", "全部时间"], id: \.self) { Text($0) }
            }.frame(width: 180).onChange(of: scope) { loadRange() }
        }
        if scope == "所选月" { monthControls }
        if scope == "自定义" {
            HStack {
                Text("开始").foregroundStyle(.secondary)
                DeadlinerDatePicker(selection: $draftStart, components: .date, in: .through(Date()))
                Text("结束（含）").foregroundStyle(.secondary)
                DeadlinerDatePicker(selection: $draftEnd, components: .date, in: .through(Date()))
                Button("应用范围", action: loadRange).buttonStyle(.borderedProminent)
            }
        }
        if let rangeError { OverviewError(message: rangeError, retry: loadRange) }
        if scope == "全部时间" {
            if let error = store.errorMessage { OverviewError(message: error, retry: refresh) }
            else {
                Menu("卡片排序") {
                    ForEach(taskOrder, id: \.self) { name in
                        Button("将「\(name)」置顶") { taskOrderRaw = ([name] + taskOrder.filter { $0 != name }).joined(separator: ",") }
                    }
                }
                ForEach(taskOrder, id: \.self) { name in
                    switch name {
                    case "今日概况": OverviewTodayCard(today: store.today)
                    case "完成时间分布": OverviewPeriodCard(periods: store.periods)
                    default: OverviewHistoryCard(history: store.history, title: "历史统计", subtitle: "全部时间")
                    }
                }
            }
        } else if rangeError != nil {
            EmptyView()
        } else if store.intervalLoading {
            ProgressView("计算所选区间…").frame(maxWidth: .infinity, minHeight: 200)
        } else if let error = store.intervalError {
            OverviewError(message: error, retry: loadRange)
        } else if let review = store.interval {
            Text("\(OverviewPeriod.key(start)) — \(OverviewPeriod.key(end)) · 指标较前一个等长周期")
                .font(.callout).foregroundStyle(.secondary)
            OverviewMetricsCard(review: review, comparison: "较上一等长周期")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: min(columns, 2)), spacing: 18) {
                OverviewHistoryCard(history: store.intervalDistribution, title: "状态分布", subtitle: "四种状态互斥",
                                    completedTiming: store.intervalTiming)
                OverviewPeriodCard(periods: store.intervalPeriods)
            }
            OverviewActivityChart(days: review.daily, title: "\(rangePhrase)完成活动")
            if let focus = store.focusInterval { OverviewFocusInvestmentCard(focus: focus) }
            OverviewCompletionTimingCard(counts: store.intervalTiming, subtitle: "\(rangePhrase)内完成的任务")
            Text("完成活动按实际完成日期；待办、逾期、放弃及指标按截止日期。指标中的逾期沿用 Core 未完成口径，含放弃。")
                .font(.caption).foregroundStyle(.secondary)
            if !review.completedTitles.isEmpty { OverviewTitlesCard(review: review, title: "\(rangePhrase)内完成的任务") }
        }
    }

    /// 当前范围的具体说法：「11月」「近30天」「2026年」「5月1日–6月2日」，用在卡片标题里代替「所选区间」。
    private var rangePhrase: String {
        let calendar = OverviewPeriod.calendar
        switch scope {
        case "所选月": return Self.monthPhrase(selectedMonth)
        case "近30天": return "近30天"
        case "本年": return "\(calendar.component(.year, from: Date()))年"
        case "自定义":
            let thisYear = calendar.component(.year, from: Date())
            let sameYear = calendar.component(.year, from: start) == thisYear && calendar.component(.year, from: end) == thisYear
            let format = sameYear ? "M月d日" : "yyyy年M月d日"
            return "\(OverviewDates.label(OverviewPeriod.key(start), format))–\(OverviewDates.label(OverviewPeriod.key(end), format))"
        default: return "全部时间"
        }
    }

    /// 「11月」；不是今年时带年份。
    static func monthPhrase(_ month: Date) -> String {
        let calendar = OverviewPeriod.calendar
        let format = calendar.component(.year, from: month) == calendar.component(.year, from: Date()) ? "M月" : "yyyy年M月"
        return OverviewDates.label(OverviewPeriod.key(month), format)
    }

    /// 所选月份每天的专注秒数。
    private var monthFocus: [String: Int] {
        Dictionary((store.focusMonth?.daily ?? []).map { ($0.start, $0.seconds) }, uniquingKeysWith: +)
    }

    private var taskOrder: [String] {
        let valid = ["今日概况", "完成时间分布", "历史统计"]
        let saved = taskOrderRaw.components(separatedBy: ",").filter { valid.contains($0) }
        return saved + valid.filter { !saved.contains($0) }
    }

    private func changeMonth(_ offset: Int) { selectedMonth = OverviewPeriod.shift(selectedMonth, months: offset); selectMonth() }
    private func selectMonth() {
        store.loadMonth(OverviewPeriod.key(selectedMonth))
        if scope == "所选月" { loadRange() }
    }
    private func refresh() { store.refresh(); loadRange(); loadInsight() }
    private func loadInsight() {
        guard store.errorMessage == nil, !store.isLoading else { return }
        insight.resolve(review: store.lastMonth)
    }
    private func loadRange() {
        let calendar = OverviewPeriod.calendar
        let today = calendar.startOfDay(for: Date())
        switch scope {
        case "所选月": start = selectedMonth; end = calendar.date(byAdding: .day, value: -1, to: OverviewPeriod.shift(selectedMonth, months: 1))!
        case "近30天": start = calendar.date(byAdding: .day, value: -29, to: today)!; end = today
        case "本年": start = calendar.date(from: calendar.dateComponents([.year], from: today))!; end = today
        case "全部时间": return
        case "自定义": start = draftStart; end = draftEnd
        default: break
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? -1
        guard days >= 0 && days < 3660 else { rangeError = "请选择 1 至 3660 天的有效日期范围"; return }
        rangeError = nil
        store.loadInterval(start: OverviewPeriod.key(start), end: OverviewPeriod.key(calendar.date(byAdding: .day, value: 1, to: end)!))
    }
}

struct OverviewError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Button("重试", action: retry)
        }
    }
}

struct OverviewActivityCalendar: View {
    let review: OverviewStore.MonthReview
    /// 当月每天的专注秒数（键为 `yyyy-MM-dd`），用于悬停提示。
    var focus: [String: Int] = [:]
    @Environment(\.palette) private var t
    var body: some View {
        OverviewCard(title: "月度活动", subtitle: "每日完成任务") {
            let weeks = OverviewHeatmapCard.weeks(review.daily)
            HStack { ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption).frame(maxWidth: .infinity) } }
            ForEach(weeks.indices, id: \.self) { index in
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { weekday in
                        if let day = weeks[index][weekday] {
                            let future = day.date > OverviewPeriod.key(Date())
                            // 悬停显示当日完成任务数与专注时长（与活跃热力图相同）。
                            Text(OverviewDates.label(day.date, "d"))
                                .font(.callout.monospacedDigit()).foregroundStyle(t.onSurface).frame(maxWidth: .infinity).frame(height: 34)
                                .background(t.primary.opacity(day.completed == 0 ? 0.04 : min(0.8, 0.18 + Double(day.completed) * 0.09)), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(day.date == OverviewPeriod.key(Date()) ? t.primary : .clear, lineWidth: 1.5))
                                .opacity(future ? 0.55 : 1)
                                .help(future ? "" : OverviewDates.dayTooltip(day, focusSeconds: focus[day.date] ?? 0))
                                .accessibilityLabel(OverviewDates.dayTooltip(day, focusSeconds: focus[day.date] ?? 0))
                        } else { Color.clear.frame(maxWidth: .infinity).frame(height: 34) }
                    }
                }
            }
        }
    }
}

struct OverviewActivityChart: View {
    let days: [OverviewStore.DayCount]
    var title = "每日完成"
    @State private var selected: Date?
    @Environment(\.palette) private var t
    var body: some View {
        OverviewCard(title: title, subtitle: "\(days.count) 天") {
            Chart(days) { day in
                BarMark(x: .value("日期", OverviewDates.date(day.date) ?? Date(), unit: .day), y: .value("完成", day.completed))
                    .foregroundStyle(OverviewColors(t: t).completed).cornerRadius(3)
            }.chartXSelection(value: $selected).frame(height: 220)
            if let selected, let day = days.first(where: { $0.date == OverviewPeriod.key(selected) }) {
                Text("\(day.date)：完成 \(day.completed) 项").font(.caption)
            } else { Text("点击图表查看每日数量").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct OverviewTrendWorkspace: View {
    let store: OverviewStore
    let columns: Int
    @AppStorage("overview.desktop.trendOrder") private var orderRaw = "年度贡献,每日完成,每月趋势,每周完成"
    private var order: [String] {
        let valid = ["年度贡献", "每日完成", "每月趋势", "每周完成", "专注时长"]
        let saved = orderRaw.components(separatedBy: ",").filter { valid.contains($0) }
        return saved + valid.filter { !saved.contains($0) }
    }
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("趋势分析").font(.title2.bold())
                Text("以今天为锚点 · 不随总览选月改变").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu("卡片排序") {
                ForEach(order, id: \.self) { name in
                    Button("将「\(name)」置顶") { orderRaw = ([name] + order.filter { $0 != name }).joined(separator: ",") }
                }
            }
        }
        if let error = store.errorMessage { OverviewError(message: error) { store.refresh() } }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: min(columns, 2)), spacing: 18) {
        ForEach(order, id: \.self) { name in
            switch name {
            case "年度贡献":
                if store.annualLoading { ProgressView("加载年度贡献…") }
                else if let error = store.annualError { OverviewError(message: error) { store.refresh() } }
                else { OverviewHeatmapCard(days: store.annual, focus: store.annualFocus) }
            case "每日完成": OverviewDailyCard(days: store.daily)
            case "每月趋势": OverviewMonthlyCard(months: store.monthly, timings: store.monthTimings)
            case "专注时长": OverviewFocusBarsCard(points: store.focusLast30?.daily ?? [], subtitle: "近 30 天", unit: .day)
            default: OverviewWeeklyCard(weeks: store.weekly)
            }
        }
        }
    }
}
