import SwiftUI

/// 任务卡片（对齐安卓 DDLItemCardSimplified）：76 高、24 圆角；
/// 纯色底 + 状态色浅层 + 剩余时间渐变进度；
/// 第一行 星标 / 标题 / 剩余时间，第二行 分类 / 子任务进度 / 备注。
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
    @Environment(\.miuix) private var t
    @State private var hovering = false

    var body: some View {
        let status = TaskStatus.indicator(task, now: now)
        let colors = status.colors(t)
        let progress = TaskStatus.remainingProgress(task, now: now)
        let remaining = TaskStatus.remainingText(task, now: now)
        let muted = task.isCompleted || task.isAbandoned

        HStack(spacing: 10) {
            Button { actions?.toggleComplete() } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.isCompleted ? t.completedCheck : t.onSurfaceVariant.opacity(task.isAbandoned ? 0.4 : 0.85))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(actions == nil || task.isAbandoned)
            .help(task.isCompleted ? "取消完成" : "标记完成")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if task.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(status.solid(t))
                    }
                    Text(task.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(t.onSurface.opacity(muted ? 0.6 : 1))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !remaining.isEmpty {
                        Text(remaining)
                            .font(.system(size: 12))
                            .foregroundStyle(t.onSurface.opacity(0.85))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let category { CategoryChip(category: category) }
                    if task.subtaskTotal > 0 { CountPill(text: "\(task.subtaskDone)/\(task.subtaskTotal)") }
                    Text(task.note)
                        .font(.system(size: 12))
                        .foregroundStyle(t.onSurfaceVariant)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, MiuixCard.padX)
        .padding(.vertical, MiuixCard.padY)
        .frame(height: MiuixCard.height)
        .background { CardBackground(colors: colors, progress: progress) }
        .clipShape(RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .shadow(color: .black.opacity(t.isDark ? 0 : (hovering ? 0.08 : 0.04)), radius: hovering ? 7 : 1, y: hovering ? 4 : 1)
        .offset(y: hovering ? -1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .onTapGesture { actions?.open() }
        .contextMenu { if let actions { menu(actions) } }
        .accessibilityElement(children: .contain)
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
