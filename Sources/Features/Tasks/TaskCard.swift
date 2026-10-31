import SwiftUI

/// 任务卡片（对齐安卓 DDLItemCardSimplified）：76 高、24 圆角；
/// 纯色底 + 状态色浅层 + 剩余时间渐变进度；
/// 第一行 星标 / 标题 / 剩余时间，第二行 分类 / 子任务进度 / 备注。
struct TaskCard: View {
    let task: TaskItem
    let category: CategoryItem?
    let now: Date
    @Environment(\.miuix) private var t
    @State private var hovering = false

    var body: some View {
        let status = TaskStatus.indicator(task, now: now)
        let colors = status.colors(t)
        let progress = TaskStatus.remainingProgress(task, now: now)
        let remaining = TaskStatus.remainingText(task, now: now)
        let muted = task.isCompleted || task.isAbandoned

        HStack(spacing: 10) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(task.isCompleted ? t.completedCheck : t.onSurfaceVariant.opacity(task.isAbandoned ? 0.4 : 0.85))

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
        .accessibilityElement(children: .combine)
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
