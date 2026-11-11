import AppKit
import SwiftUI

/// 任务卡片：76 高、28 圆角；纯色底 + 状态色浅层 + 剩余时间渐变进度（色块与 Android 一致）。
/// 第一行 星标 / 标题 / 分类 / 剩余时间，第二行 子任务进度 / 备注（没有备注时保留空行，标题位置固定）。
/// 不显示勾选框：完成等操作在悬停按钮、右键菜单与编辑器中。
struct TaskCard: View {
    /// 卡片上的操作；为 nil 时卡片只读（截图测试使用）。
    struct Actions {
        var toggleComplete: () -> Void
        var open: () -> Void
        var toggleStar: () -> Void
        var toggleGiveUp: () -> Void
        var archive: () -> Void
        var delete: () -> Void
        /// 延期：数量与单位（true 为小时）。
        var postpone: (Int, Bool) -> Void = { _, _ in }
        /// 选中 / 取消选中（多选）。
        var select: () -> Void = {}
    }

    let task: TaskItem
    let category: CategoryItem?
    let now: Date
    var actions: Actions?
    /// 多选时是否选中；nil 表示不在多选状态。
    var selected: Bool?
    @AppStorage(TaskDisplaySettings.forwardProgressKey) private var forwardProgress = false
    @AppStorage(TaskDisplaySettings.detailedRemainingKey) private var detailedRemaining = true
    @Environment(\.palette) private var t
    @State private var hovering = false

    var body: some View {
        let status = TaskStatus.indicator(task, now: now)
        let colors = status.colors(t)
        let progress = TaskStatus.displayedProgress(task, now: now, forward: forwardProgress)
        let remaining = TaskStatus.remainingText(task, now: now, detailed: detailedRemaining)
        let muted = task.isCompleted || task.isAbandoned

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if task.isStarred {
                    Image(systemName: "star.fill")
                        .font(.title3)
                        .foregroundStyle(status.solid(t))
                }
                Text(task.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(t.onSurface.opacity(muted ? 0.6 : 1))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let category { CategoryChip(category: category) }
                if !remaining.isEmpty {
                    Text(remaining)
                        .font(.caption)
                        .foregroundStyle(t.onSurface.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(minHeight: 24)
            HStack(spacing: 6) {
                if task.subtaskTotal > 0 { CountPill(text: "\(task.subtaskDone)/\(task.subtaskTotal)") }
                Text(task.note.isEmpty ? "\u{00A0}" : task.note)
                    .font(.caption)
                    .foregroundStyle(t.onSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, MiuixCard.padX)
        .padding(.vertical, MiuixCard.padY)
        .frame(height: MiuixCard.height)
        .background { CardBackground(colors: colors, sweepFrom: IndicatorStatus.undergo.colors(t), progress: progress, forward: forwardProgress) }
        .overlay(alignment: .bottomTrailing) {
            if let actions, hovering, selected == nil { hoverActions(actions) }
        }
        .overlay {
            if let selected {
                RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous)
                    .strokeBorder(selected ? t.primary : t.onSurface.opacity(0.15), lineWidth: selected ? 2.5 : 1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let selected {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? t.primary : t.onSurfaceVariant)
                    .background(Circle().fill(t.cardBase).padding(2))
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .shadow(color: .black.opacity(t.isDark ? 0 : (hovering ? 0.08 : 0.04)), radius: hovering ? 7 : 1, y: hovering ? 4 : 1)
        .offset(y: hovering ? -1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .onTapGesture {
            // 多选中点按切换选中；⌘ 点按进入多选。
            if selected != nil || NSEvent.modifierFlags.contains(.command) { actions?.select() } else { actions?.open() }
        }
        .contextMenu {
            if let actions {
                Button(task.isCompleted ? "取消完成" : "标记完成", systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle",
                       action: actions.toggleComplete)
                    .disabled(task.isAbandoned)
                menu(actions)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 悬停时浮在右下角的玻璃按钮：完成 / 取消完成，以及「更多」菜单（与右键菜单相同），不占用卡片布局。
    private func hoverActions(_ actions: Actions) -> some View {
        HStack(spacing: 6) {
            if !task.isAbandoned {
                Button(action: actions.toggleComplete) {
                    Label(task.isCompleted ? "取消完成" : "完成", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .deadlinerGlass(in: Capsule(), interactive: true)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(task.isCompleted ? "取消完成" : "标记完成")
            }
            Menu { menu(actions) } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 24)
                    .deadlinerGlass(in: Capsule(), interactive: true)
                    .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
        }
        .foregroundStyle(t.onSurface)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    @ViewBuilder
    private func menu(_ actions: Actions) -> some View {
        Button("编辑", systemImage: "pencil", action: actions.open)
        Button(task.isStarred ? "取消标星" : "标星", systemImage: task.isStarred ? "star.slash" : "star", action: actions.toggleStar)
        if task.state == .active, task.dueAt != nil {
            Menu("延期", systemImage: "calendar.badge.clock") {
                ForEach(TaskDisplaySettings.postponeOptions, id: \.title) { option in
                    Button(option.title) { actions.postpone(option.amount, option.hours) }
                }
            }
        }
        if TaskCommands.canApply(.markGiveUp, to: task.state) {
            Button(task.isAbandoned ? "取消放弃" : "放弃", systemImage: task.isAbandoned ? "arrow.uturn.backward" : "nosign", action: actions.toggleGiveUp)
        }
        Button(TaskCommands.canApply(.markArchive, to: task.state) ? "归档" : "归档（需先完成或放弃）", systemImage: "archivebox", action: actions.archive)
            .disabled(!TaskCommands.canApply(.markArchive, to: task.state))
        Divider()
        Button("选择", systemImage: "checkmark.circle", action: actions.select)
        Button("删除", systemImage: "trash", role: .destructive, action: actions.delete)
    }
}

/// 卡片背景：底色、状态色浅层、从左到右的剩余时间渐变。
///
/// 进度条不跟随数值做隐式动画：列表刷新（完成、编辑、同步）时卡片可能换位置，隐式动画会把位置变化
/// 一起动画化，色块就会从旧位置飘过来。改为：列表内容或排列方式一变（`cardSweepKey`），
/// 就在卡片当前位置重新创建色块，从满格缩回当前值（正向进度条时从零向右增长到当前值）；
/// 每分钟的时间流逝只静默更新进度。
private struct CardBackground: View {
    let colors: IndicatorStatus.Colors
    let sweepFrom: IndicatorStatus.Colors
    let progress: Double
    var forward = false
    @Environment(\.cardSweepKey) private var sweepKey

    var body: some View {
        ZStack(alignment: .leading) {
            colors.base
            colors.overlay
            if progress > 0 {
                SweepBar(colors: colors, sweepFrom: sweepFrom, progress: progress, forward: forward)
                    // 新的 key 就是新的色块：不在新旧位置之间插值，也不做淡入淡出。
                    .id(sweepKey)
                    .transition(.identity)
            }
        }
    }
}

/// 一次性的进度色块：出现时为满格（「进行中」的颜色），排好位置后缩回当前进度并过渡到当前状态色。
/// 正向进度条（随时间增长）时反过来：从零开始向右增长到当前进度。
private struct SweepBar: View {
    let colors: IndicatorStatus.Colors
    let sweepFrom: IndicatorStatus.Colors
    let progress: Double
    var forward = false
    @State private var sweeping = true

    var body: some View {
        ZStack {
            gradient(sweepFrom)
            gradient(colors).opacity(sweeping ? 0 : 1)
        }
        .scaleEffect(x: sweeping ? (forward ? 0.001 : 1) : progress, y: 1, anchor: .leading)
        .onAppear {
            // 等卡片在当前位置排好之后再开始动画，否则位置变化会被一起动画化。
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.8)) { sweeping = false }
            }
        }
    }

    private func gradient(_ c: IndicatorStatus.Colors) -> some View {
        LinearGradient(colors: [c.indicatorStart, c.indicator], startPoint: .leading, endPoint: .trailing)
    }
}

extension EnvironmentValues {
    /// 列表内容与排列方式的签名；变化时每张卡片在当前位置重新播放进度回落动画。
    @Entry var cardSweepKey: String = ""
}
