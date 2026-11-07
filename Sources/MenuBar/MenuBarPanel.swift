import SwiftUI

/// 菜单栏面板：读取 AppModel 与设置，交给不依赖 Core 的 `MenuBarPanelContent` 渲染。
struct MenuBarPanel: View {
    let model: AppModel
    var close: () -> Void
    var openMain: () -> Void
    @AppStorage(MenuBarSettings.panelStyleKey) private var styleRaw = PanelStyle.list.rawValue
    @AppStorage(MenuBarSettings.sectionsKey) private var sectionsRaw = PanelSection.encode(PanelSection.defaults)
    @AppStorage(MenuBarSettings.focusChartKey) private var focusChartRaw = FocusChartOrientation.vertical.rawValue
    @AppStorage(MenuBarSettings.statsKey) private var statsRaw = PanelStat.encode(PanelStat.defaults)
    @AppStorage(MenuBarSettings.upcomingRangeKey) private var upcomingRaw = UpcomingRange.all.rawValue
    @AppStorage(MenuBarSettings.upcomingCustomRangeKey) private var upcomingCustomRaw = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            MenuBarPanelContent(
                summary: model.menuBarSummary(now: context.date),
                style: PanelStyle(rawValue: styleRaw) ?? .list,
                sections: PanelSection.decode(sectionsRaw),
                syncStatus: model.sync.status,
                now: context.date,
                focusOrientation: FocusChartOrientation(rawValue: focusChartRaw) ?? .vertical,
                stats: Array(PanelStat.decode(statsRaw).prefix(PanelStat.maxCount)),
                upcomingRange: UpcomingRange(rawValue: upcomingRaw) ?? .all,
                upcomingCustomRange: DateRange.decode(upcomingCustomRaw),
                timerRow: timerRow,
                actions: .init(
                    completeTask: { id in try? model.taskCommands.toggleComplete(id) },
                    checkHabit: { habit in model.habitList.applyPrimaryAction(habit) },
                    newTask: { model.newTask(); openMain() },
                    openMain: openMain,
                    syncNow: { model.sync.syncNow() },
                    openSettings: { model.page = .settings; openMain() },
                    quit: { NSApp.terminate(nil) }
                )
            )
        }
    }

    /// 正在专注时，面板标题下方的计时行（在面板的玻璃背景之内）。
    private var timerRow: AnyView? {
        guard let running = model.focusTimer.running else { return nil }
        return AnyView(FocusPanelTimerRow(timer: model.focusTimer, running: running) {
            close()
            NSApp.activate(ignoringOtherApps: true)
            (NSApp.delegate as? AppDelegate)?.openFocusWindowAction?()
        })
    }
}

struct MenuBarPanelContent: View {
    struct Actions {
        var completeTask: (String) -> Void
        var checkHabit: (HabitItem) -> Void
        var newTask: () -> Void
        var openMain: () -> Void
        var syncNow: () -> Void
        var openSettings: () -> Void
        var quit: () -> Void
    }

    let summary: MenuBarSummary
    let style: PanelStyle
    let sections: [PanelSection]
    let syncStatus: SyncController.Status
    let now: Date
    var focusOrientation: FocusChartOrientation = .vertical
    var stats: [PanelStat] = PanelStat.defaults
    var upcomingRange: UpcomingRange = .all
    var upcomingCustomRange: DateRange?
    /// 专注计时行（由 `MenuBarPanel` 提供，这里不依赖 Core）。
    var timerRow: AnyView?
    var actions: Actions?
    @State private var hoveredFocusDay: String?
    @Environment(\.palette) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let timerRow {
                timerRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(sections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            Divider().padding(.horizontal, 14)
            footer
        }
        .frame(width: style == .dashboard ? 360 : 330)
        .fixedSize(horizontal: false, vertical: true)
        .deadlinerGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Header & footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconImage.image)
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Deadliner").font(.headline)
                Text(now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if summary.overdue > 0 {
                Label("\(summary.overdue) 项逾期", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(t.error)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var footer: some View {
        switch style {
        case .list:
            VStack(alignment: .leading, spacing: 0) {
                MenuRow(title: "打开 Deadliner", systemImage: "macwindow", action: actions?.openMain)
                MenuRow(title: "立即同步", systemImage: "arrow.triangle.2.circlepath", shortcut: "⌘R", action: actions?.syncNow)
                MenuRow(title: "设置…", systemImage: "gearshape", shortcut: "⌘,", action: actions?.openSettings)
                MenuRow(title: "退出 Deadliner", systemImage: "power", shortcut: "⌘Q", action: actions?.quit)
            }
            .padding(6)
        case .dashboard:
            HStack(spacing: 6) {
                footerButton("打开", "macwindow", actions?.openMain)
                footerButton("同步", "arrow.triangle.2.circlepath", actions?.syncNow)
                footerButton("设置", "gearshape", actions?.openSettings)
                Spacer()
                footerButton("退出", "power", actions?.quit)
            }
            .padding(10)
        }
    }

    private func footerButton(_ title: String, _ icon: String, _ action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Label(title, systemImage: icon).font(.caption.weight(.medium))
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(_ section: PanelSection) -> some View {
        switch section {
        case .overview: overview
        case .tasks: tasks
        case .habits: habits
        case .focusChart: focusChart
        case .quickAdd: quickAdd
        case .sync: syncRow
        }
    }

    @ViewBuilder
    private var overview: some View {
        switch style {
        case .dashboard:
            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    ProgressRing(fraction: summary.habitFraction, size: 78)
                    Text("习惯").font(.caption2).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(stats) { stat in statTile(stat.title, summary.value(for: stat), tint(stat)) }
                }
            }
            .padding(.bottom, 8)
        case .list:
            HStack(spacing: 8) {
                ForEach(stats) { stat in statTile(stat.title, summary.value(for: stat), tint(stat)) }
            }
        }
    }

    private func tint(_ stat: PanelStat) -> Color {
        switch stat {
        case .dueToday, .dueTomorrow, .dueThisWeek, .pendingThisWeek: t.tertiary
        case .overdue: t.error
        case .active, .activeToday, .activeThisWeek, .habits: t.primary
        case .focusToday, .focusThisWeek: Color(hex: 0x10B981)
        }
    }

    private func statTile(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(tint)
            Text(value).font(.title3.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var tasks: some View {
        let lines = summary.upcoming(in: upcomingRange, now: now, custom: upcomingCustomRange)
        let rangeTitle = upcomingRange == .custom ? (upcomingCustomRange?.label ?? "自定义") : upcomingRange.title
        let limit = style == .dashboard ? 4 : 6
        HStack {
            sectionTitle(upcomingRange == .all ? "即将到期" : "即将到期 · \(rangeTitle)")
            Spacer()
            if lines.count > limit {
                Text("还有 \(lines.count - limit) 个").font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
        if lines.isEmpty {
            Text(upcomingRange == .all ? "没有有截止时间的待办" : "\(rangeTitle)没有到期的待办")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(lines.prefix(limit)) { line in
                    TaskLineRow(line: line) { actions?.completeTask(line.id) }
                }
            }
        }
    }

    @ViewBuilder
    private var habits: some View {
        sectionTitle("今日习惯 \(summary.habitsDone)/\(summary.habitsTotal)")
        if summary.habits.isEmpty {
            Text("今天没有需要打卡的习惯").font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(summary.habits.prefix(6)) { habit in
                    HabitLineRow(habit: habit) { actions?.checkHabit(habit) }
                }
            }
        }
    }

    @ViewBuilder
    private var focusChart: some View {
        let peak = max(1, summary.focusDays.map(\.seconds).max() ?? 1)
        let total = summary.focusDays.map(\.seconds).reduce(0, +)
        HStack {
            sectionTitle("最近 7 天专注")
            Spacer()
            // 悬停在某一天上时显示那天的时长，否则显示 7 天合计。
            Group {
                if let day = hoveredFocusDay, let point = summary.focusDays.first(where: { $0.id == day }) {
                    Text("周\(point.label) · \(FocusTexts.duration(point.seconds))")
                } else if total > 0 {
                    Text("合计 \(FocusTexts.duration(total))")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        if summary.focusDays.isEmpty {
            Text("还没有专注记录").font(.callout).foregroundStyle(.secondary)
        } else {
            switch focusOrientation {
            case .vertical: verticalFocusBars(peak: peak)
            case .horizontal: horizontalFocusBars(peak: peak)
            }
        }
    }

    /// 竖向：细长的胶囊柱，日期在下方。
    private func verticalFocusBars(peak: Int) -> some View {
        let height: CGFloat = style == .dashboard ? 84 : 60
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(summary.focusDays) { day in
                VStack(spacing: 5) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.primary.opacity(0.06)).frame(width: 8, height: height)
                        Capsule()
                            .fill(Color(hex: 0x10B981).gradient)
                            .frame(width: 8, height: day.seconds == 0 ? 0 : max(8, height * CGFloat(day.seconds) / CGFloat(peak)))
                            .opacity(hoveredFocusDay == nil || hoveredFocusDay == day.id ? 1 : 0.45)
                    }
                    Text(day.label).font(.caption2).foregroundStyle(hoveredFocusDay == day.id ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onHover { hoveredFocusDay = $0 ? day.id : (hoveredFocusDay == day.id ? nil : hoveredFocusDay) }
                .help("周\(day.label)：\(FocusTexts.duration(day.seconds))")
            }
        }
        .animation(.easeOut(duration: 0.15), value: hoveredFocusDay)
    }

    /// 横向：每天一行细条，右侧显示时长。
    private func horizontalFocusBars(peak: Int) -> some View {
        VStack(spacing: 7) {
            ForEach(summary.focusDays) { day in
                HStack(spacing: 8) {
                    Text(day.label).font(.caption2).foregroundStyle(.secondary).frame(width: 14)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(Color(hex: 0x10B981).gradient)
                                .frame(width: day.seconds == 0 ? 0 : max(6, proxy.size.width * CGFloat(day.seconds) / CGFloat(peak)))
                        }
                    }
                    .frame(height: 6)
                    Text(day.seconds == 0 ? "—" : FocusTexts.compact(day.seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .opacity(hoveredFocusDay == nil || hoveredFocusDay == day.id ? 1 : 0.55)
                .contentShape(Rectangle())
                .onHover { hoveredFocusDay = $0 ? day.id : (hoveredFocusDay == day.id ? nil : hoveredFocusDay) }
                .help("周\(day.label)：\(FocusTexts.duration(day.seconds))")
            }
        }
        .animation(.easeOut(duration: 0.15), value: hoveredFocusDay)
    }

    private var quickAdd: some View {
        Button { actions?.newTask() } label: {
            Label("新建任务…", systemImage: "plus")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundStyle(.white)
                .deadlinerGlass(in: Capsule(), tint: t.accentFab, interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var syncRow: some View {
        let (icon, text, tint): (String, String, Color) = switch syncStatus {
        case .disabled: ("icloud.slash", "未启用同步", .secondary)
        case .backingUp: ("arrow.down.doc", "正在备份云端…", t.primary)
        case .awaitingConfirmation: ("questionmark.circle", "同步等待确认", .orange)
        case .idle: ("icloud", "等待同步", .secondary)
        case .syncing: ("arrow.triangle.2.circlepath", "正在同步…", t.primary)
        case .succeeded(let date): ("checkmark.icloud", "已同步 \(date.formatted(date: .omitted, time: .shortened))", .green)
        case .failed(let reason): ("exclamationmark.icloud", "同步失败：\(reason)", .red)
        }
        return Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

/// 面板中的任务行：状态色圆点、标题、剩余时间，悬停时出现完成按钮。
private struct TaskLineRow: View {
    let line: MenuBarSummary.TaskLine
    var complete: () -> Void
    @Environment(\.palette) private var t
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(line.status.solid(t)).frame(width: 7, height: 7)
            if line.isStarred {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(line.status.solid(t))
            }
            Text(line.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            if hovering {
                Button(action: complete) { Image(systemName: "checkmark.circle") }
                    .buttonStyle(.borderless)
                    .help("标记完成")
            } else {
                Text(line.remaining)
                    .font(.caption)
                    .foregroundStyle(line.status == .passed ? t.error : .secondary)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
    }
}

/// 面板中的习惯行：打卡按钮（勾选型 / 计量型）、名称、进度。
private struct HabitLineRow: View {
    let habit: HabitItem
    var check: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        HStack(spacing: 8) {
            Button(action: check) {
                if habit.actionKind == .addQuantity && !habit.isCompleted {
                    Text("+\(habit.actionAmount)").font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).frame(height: 18)
                        .background(t.primary.opacity(habit.canApplyPrimaryAction ? 1 : 0.3), in: Capsule())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(habit.isCompleted ? t.completedCheck : .secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!habit.canApplyPrimaryAction)
            .help(HabitTexts.actionHelp(habit))
            Text(habit.name).lineLimit(1)
            Spacer(minLength: 6)
            Text(HabitTexts.progress(habit)).font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(height: 28)
    }
}

/// 列表菜单风格中的菜单项：悬停高亮，右侧显示快捷键。
private struct MenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    var action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(.secondary) }
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
