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
    }

    let task: TaskItem
    let category: CategoryItem?
    let now: Date
    var actions: Actions?
    @Environment(\.palette) private var t
    @State private var hovering = false

    var body: some View {
        let status = TaskStatus.indicator(task, now: now)
        let colors = status.colors(t)
        let progress = TaskStatus.remainingProgress(task, now: now)
        let remaining = TaskStatus.remainingText(task, now: now)
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
        .background { CardBackground(colors: colors, progress: progress) }
        .overlay(alignment: .bottomTrailing) {
            if let actions, hovering { hoverActions(actions) }
        }
        .clipShape(RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .shadow(color: .black.opacity(t.isDark ? 0 : (hovering ? 0.08 : 0.04)), radius: hovering ? 7 : 1, y: hovering ? 4 : 1)
        .offset(y: hovering ? -1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .onTapGesture { actions?.open() }
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
        if TaskCommands.canApply(.markGiveUp, to: task.state) {
            Button(task.isAbandoned ? "取消放弃" : "放弃", systemImage: task.isAbandoned ? "arrow.uturn.backward" : "nosign", action: actions.toggleGiveUp)
        }
        Button(TaskCommands.canApply(.markArchive, to: task.state) ? "归档" : "归档（需先完成或放弃）", systemImage: "archivebox", action: actions.archive)
            .disabled(!TaskCommands.canApply(.markArchive, to: task.state))
        Divider()
        Button("删除", systemImage: "trash", role: .destructive, action: actions.delete)
    }
}

/// 卡片背景：底色、状态色浅层、从左到右的剩余时间渐变。
private struct CardBackground: View {
    let colors: IndicatorStatus.Colors
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                colors.base
                colors.overlay
                if progress > 0 {
                    LinearGradient(colors: [colors.indicatorStart, colors.indicator], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * progress)
                        .animation(.easeOut(duration: 0.5), value: progress)
                }
            }
        }
    }
}
