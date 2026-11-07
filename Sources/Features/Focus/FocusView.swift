import SwiftUI

/// 专注记录页：今天 / 本周 / 本月 / 累计 四个汇总块，下面按日期分组列出最近的专注。
/// 在任务或习惯的编辑器中开始专注（计时窗）；这里可以调整记录的时长（只能改短）或删除记录，与 Android 专注管理一致。
struct FocusView: View {
    let store: FocusStore
    @State private var adjusting: FocusStore.Session?
    @State private var pendingDelete: FocusStore.Session?
    @State private var errorMessage: String?

    var body: some View {
        FocusContent(
            today: store.today, thisWeek: store.thisWeek, thisMonth: store.thisMonth, allTime: store.allTime,
            sessions: store.sessions,
            onAdjust: { adjusting = $0 },
            onDelete: { pendingDelete = $0 }
        )
        .topAtmosphere(Color(hex: 0x10B981))
        .navigationTitle("专注")
        .navigationSubtitle("在任务或习惯中开始专注；右键记录可以调整时长或删除")
        .onAppear { store.refresh() }
        .sheet(item: $adjusting) { session in
            FocusAdjustSheet(session: session) { seconds in
                adjusting = nil
                store.adjust(session.id, seconds: seconds) { errorMessage = $0 }
            } onCancel: {
                adjusting = nil
            }
        }
        .confirmationDialog("删除这条专注记录？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { session in
            Button("删除", role: .destructive) { store.delete(session.id) { errorMessage = $0 } }
        } message: { session in
            Text("「\(session.title.isEmpty ? "未命名" : session.title)」\(FocusTexts.duration(session.durationSeconds))。删除会同步到其他设备。")
        }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

/// 调整专注时长：只能在 1 分钟到原时长之间（Core 的规则）。
private struct FocusAdjustSheet: View {
    let session: FocusStore.Session
    var onSave: (Int) -> Void
    var onCancel: () -> Void
    @State private var minutes: Int

    init(session: FocusStore.Session, onSave: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.onSave = onSave
        self.onCancel = onCancel
        _minutes = State(initialValue: max(1, session.durationSeconds / 60))
    }

    private var maxMinutes: Int { max(1, session.durationSeconds / 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("调整专注时长").font(.headline)
            Text(verbatim: session.title.isEmpty ? "未命名" : session.title).foregroundStyle(.secondary)
            Stepper(value: $minutes, in: 1...maxMinutes) {
                Text("\(minutes) 分钟").font(.title3.monospacedDigit())
            }
            Text("原时长 \(FocusTexts.duration(session.durationSeconds))；只能改短。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { onSave(minutes * 60) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(minutes * 60 >= session.durationSeconds)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct FocusContent: View {
    let today: FocusStore.Summary
    let thisWeek: FocusStore.Summary
    let thisMonth: FocusStore.Summary
    let allTime: FocusStore.Summary
    let sessions: [FocusStore.Session]
    var onAdjust: ((FocusStore.Session) -> Void)?
    var onDelete: ((FocusStore.Session) -> Void)?
    @Environment(\.palette) private var t

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    tile("今天", today, tint: t.primary)
                    tile("本周", thisWeek, tint: Color(hex: 0x10B981))
                    tile("本月", thisMonth, tint: Color(hex: 0xF59E0B))
                    tile("累计", allTime, tint: Color(hex: 0x8B5CF6))
                }
                .padding(.vertical, 4)
            }
            if sessions.isEmpty {
                Section {
                    Label("还没有专注记录", systemImage: "timer")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            } else {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { session in row(session) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .readableWidth(860)
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
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(FocusTexts.duration(session.durationSeconds))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text([FocusTexts.timeRange(session), session.isCountdown ? "倒计时" : "正计时", FocusTexts.completion(session.completionKind)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                HStack(spacing: 6) {
                    Text(session.title.isEmpty ? "（未命名）" : session.title).lineLimit(1)
                    // 超前、提前完成的任务加一个与卡片同色的标签。
                    if let timing = session.timing, timing == .ahead || timing == .early {
                        let color = timing.status.solid(t)
                        Text(timing.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(color.opacity(0.15), in: Capsule())
                    }
                }
            } icon: {
                Image(systemName: session.isHabit ? "target" : "checklist")
                    .foregroundStyle(session.isHabit ? Color(hex: 0x10B981) : t.primary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let onAdjust, let onDelete {
                Button("调整时长…", systemImage: "timer") { onAdjust(session) }
                    .disabled(session.durationSeconds < 120)
                Button("删除", systemImage: "trash", role: .destructive) { onDelete(session) }
            }
        }
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
    /// 菜单栏用的短格式，例如「1h20」「45m」。
    static func compact(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)" }
        return "\(minutes)m"
    }

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
