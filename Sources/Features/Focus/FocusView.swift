import SwiftUI

/// 专注记录页（只读）：今天 / 本周 / 本月 / 累计 四个汇总块，下面按日期分组列出最近的专注。
struct FocusView: View {
    let store: FocusStore

    var body: some View {
        FocusContent(
            today: store.today, thisWeek: store.thisWeek, thisMonth: store.thisMonth, allTime: store.allTime,
            sessions: store.sessions
        )
        .onAppear { store.refresh() }
    }
}

struct FocusContent: View {
    let today: FocusStore.Summary
    let thisWeek: FocusStore.Summary
    let thisMonth: FocusStore.Summary
    let allTime: FocusStore.Summary
    let sessions: [FocusStore.Session]
    @Environment(\.palette) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("专注")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(t.onSurface)
                Text("Mac 端只读，专注计时请在手机上进行")
                    .font(.system(size: 13))
                    .foregroundStyle(t.onSurfaceVariant)
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        tile("今天", today, tint: t.primary)
                        tile("本周", thisWeek, tint: Color(hex: 0x10B981))
                        tile("本月", thisMonth, tint: Color(hex: 0xF59E0B))
                        tile("累计", allTime, tint: Color(hex: 0x8B5CF6))
                    }
                    if sessions.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "timer").font(.system(size: 36))
                            Text("还没有专注记录").font(.callout)
                        }
                        .foregroundStyle(t.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(groups, id: \.title) { group in
                            MiuixGroup(title: group.title) {
                                ForEach(group.sessions) { session in row(session) }
                            }
                        }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.pageBg)
    }

    private func tile(_ title: String, _ summary: FocusStore.Summary, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(FocusTexts.duration(summary.totalSeconds))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(t.onSurface)
            Text("\(summary.sessionCount) 次专注")
                .font(.system(size: 12))
                .foregroundStyle(t.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(t.groupBg, in: RoundedRectangle(cornerRadius: MiuixRadius.group, style: .continuous))
    }

    private func row(_ session: FocusStore.Session) -> some View {
        MiuixRow(title: session.title.isEmpty ? "（未命名）" : session.title,
                 systemImage: session.isHabit ? "target" : "checklist",
                 tint: session.isHabit ? Color(hex: 0x10B981) : t.primary) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(FocusTexts.duration(session.durationSeconds))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.onSurface)
                Text([FocusTexts.timeRange(session), session.isCountdown ? "倒计时" : "正计时", FocusTexts.completion(session.completionKind)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.onSurfaceVariant)
            }
        }
        .padding(.vertical, 2)
    }

    private var groups: [(title: String, sessions: [FocusStore.Session])] {
        var result: [(title: String, sessions: [FocusStore.Session])] = []
        for session in sessions {
            let title = session.startedAt.map(FocusTexts.dayTitle) ?? "未知日期"
            if result.last?.title == title {
                result[result.count - 1].sessions.append(session)
            } else {
                result.append((title, [session]))
            }
        }
        return result
    }
}

enum FocusTexts {
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60)小时" : "\(minutes / 60)小时\(minutes % 60)分" }
        if minutes > 0 { return "\(minutes)分钟" }
        return "\(seconds)秒"
    }

    static func timeRange(_ session: FocusStore.Session) -> String? {
        guard let start = session.startedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let end = session.endedAt else { return formatter.string(from: start) }
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let sameYear = parts.year == calendar.component(.year, from: Date())
        return sameYear ? "\(parts.month!)月\(parts.day!)日" : "\(parts.year!)年\(parts.month!)月\(parts.day!)日"
    }

    static func completion(_ kind: String) -> String? {
        switch kind {
        case "FOCUS_AND_TASK_COMPLETED": "完成了任务"
        case "FOCUS_AND_HABIT_RECORDED": "记录了习惯"
        case "COUNTDOWN_ELAPSED": "倒计时结束"
        default: nil
        }
    }
}
