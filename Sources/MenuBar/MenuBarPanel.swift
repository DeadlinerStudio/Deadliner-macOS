import Charts
import SwiftUI

/// 菜单栏面板：读取 AppModel 与设置，交给不依赖 Core 的 `MenuBarPanelContent` 渲染。
struct MenuBarPanel: View {
    let model: AppModel
    var close: () -> Void
    var openMain: () -> Void
    @AppStorage(MenuBarSettings.panelStyleKey) private var styleRaw = PanelStyle.list.rawValue
    @AppStorage(MenuBarSettings.sectionsKey) private var sectionsRaw = PanelSection.encode(PanelSection.defaults)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            MenuBarPanelContent(
                summary: model.menuBarSummary(now: context.date),
                style: PanelStyle(rawValue: styleRaw) ?? .list,
                sections: PanelSection.decode(sectionsRaw),
                syncStatus: model.sync.status,
                now: context.date,
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
    var actions: Actions?
    @Environment(\.palette) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 520)
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
                ProgressRing(fraction: summary.habitFraction, size: 78)
                    .overlay(alignment: .bottom) {
                        Text("习惯").font(.caption2).foregroundStyle(.secondary).offset(y: 14)
                    }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    statTile("今天到期", "\(summary.dueToday)", t.tertiary)
                    statTile("已逾期", "\(summary.overdue)", t.error)
                    statTile("进行中", "\(summary.activeCount)", t.primary)
                    statTile("今日专注", FocusTexts.compact(summary.focusTodaySeconds), Color(hex: 0x10B981))
                }
            }
            .padding(.bottom, 8)
        case .list:
            HStack(spacing: 8) {
                statTile("今天到期", "\(summary.dueToday)", t.tertiary)
                statTile("已逾期", "\(summary.overdue)", t.error)
                statTile("习惯", "\(summary.habitsDone)/\(summary.habitsTotal)", t.primary)
            }
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
        sectionTitle("即将到期")
        if summary.upcoming.isEmpty {
            Text("没有有截止时间的待办").font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(summary.upcoming.prefix(style == .dashboard ? 4 : 6)) { line in
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
        sectionTitle("最近 7 天专注")
        if summary.focusDays.isEmpty {
            Text("还没有专注记录").font(.callout).foregroundStyle(.secondary)
        } else {
            Chart(summary.focusDays) { day in
                BarMark(x: .value("日期", day.label), y: .value("分钟", Double(day.seconds) / 60))
                    .foregroundStyle(Color(hex: 0x10B981).gradient)
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .frame(height: style == .dashboard ? 90 : 64)
        }
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
