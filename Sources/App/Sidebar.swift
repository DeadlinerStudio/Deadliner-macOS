import SwiftUI

/// 系统侧栏：任务 / 习惯｜专注 / 归档｜设置，底部显示同步状态。
struct Sidebar: View {
    @Binding var page: AppModel.Page
    /// 底部的同步状态；为 nil 时不显示。
    var syncStatus: SyncController.Status?
    /// 「立即同步」按钮的动作；为 nil 时不显示按钮。
    var syncNow: (() -> Void)?
    /// 顶部的个人资料；为 nil 时不显示。
    var profile: ProfileStore?
    var editProfile: () -> Void = {}
    /// 「任务」「习惯」角标的数据来源；为 nil 时不显示角标。
    var taskList: TaskListStore?
    var habitList: HabitListStore?
    @Environment(\.palette) private var t
    @State private var hoveringProfile = false

    private static let groups: [(title: String?, pages: [AppModel.Page])] = [
        (nil, [.tasks, .habits, .capture]),
        ("记录", [.overview, .focus, .archive]),
        (nil, [.settings]),
    ]

    var body: some View {
        List(selection: Binding(get: { page }, set: { if let value = $0 { page = value } })) {
            ForEach(Self.groups.indices, id: \.self) { index in
                let group = Self.groups[index]
                Section {
                    ForEach(group.pages) { page in
                        Label {
                            Text(page.title)
                        } icon: {
                            IconTile(systemImage: page.systemImage, color: page.tint)
                        }
                        .badge(badge(for: page))
                        .tag(page)
                    }
                } header: {
                    if let title = group.title { Text(title) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            if let profile { profileHeader(profile) }
        }
        .safeAreaInset(edge: .bottom) {
            if let syncStatus { syncFooter(syncStatus) }
        }
    }

    /// 侧栏角标：任务为今天到期与已逾期的进行中任务，习惯为今天还没打卡的习惯；0 时不显示。
    private func badge(for page: AppModel.Page) -> Int {
        switch page {
        case .tasks: taskList.map { Self.dueTaskCount($0.tasks, now: Date()) } ?? 0
        case .habits: habitList.map { Self.pendingHabitCount(selectedDate: $0.selectedDate, daily: $0.dailyHabits, week: $0.week, now: Date()) } ?? 0
        default: 0
        }
    }

    /// 进行中、截止时间不晚于今天结束的任务数（含已逾期）。
    static func dueTaskCount(_ tasks: [TaskItem], now: Date, calendar: Calendar = .current) -> Int {
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return 0 }
        return tasks.filter { task in
            guard task.state == .active, let due = task.dueAt else { return false }
            return due < endOfToday
        }.count
    }

    /// 今天应打卡、还没完成的习惯数。习惯页选中的是今天时按习惯逐个计算，否则用本周概览里今天的数字。
    static func pendingHabitCount(selectedDate: String, daily: [HabitItem], week: [HabitDay], now: Date) -> Int {
        let today = HabitDates.string(now)
        if selectedDate == today {
            return daily.filter { $0.isDue && !$0.isCompleted }.count
        }
        guard let day = week.first(where: { $0.date == today }) else { return 0 }
        return max(0, day.total - day.completed)
    }

    /// 头像与昵称，点击编辑个人资料。
    private func profileHeader(_ profile: ProfileStore) -> some View {
        Button(action: editProfile) {
            HStack(spacing: 10) {
                ProfileAvatar(store: profile, size: 34)
                    .overlay(Circle().strokeBorder(t.primary.opacity(0.35), lineWidth: 1.5).padding(-2.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(Self.greeting(Date())) · \(Date().formatted(.dateTime.month().day().weekday()))")
                        .font(.caption)
                        .foregroundStyle(t.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(t.onSurfaceVariant)
                    .opacity(hoveringProfile ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(t.onSurface.opacity(hoveringProfile ? 0.08 : 0.04))
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringProfile = $0 }
        .help("编辑个人资料")
    }

    /// 按时间段的问候（与 Android 首页问候的时间段一致）。
    static func greeting(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<9: "早上好"
        case 9..<12: "上午好"
        case 12..<14: "中午好"
        case 14..<18: "下午好"
        case 18..<23: "晚上好"
        default: "夜深了，早点休息"
        }
    }

    private func syncFooter(_ status: SyncController.Status) -> some View {
        let (icon, text, tint): (String, String, Color) = switch status {
        case .disabled: ("icloud.slash", "未启用同步", t.onSurfaceVariant)
        case .backingUp: ("arrow.down.doc", "正在备份云端…", t.primary)
        case .awaitingConfirmation: ("questionmark.circle", "等待确认", Color(hex: 0xF59E0B))
        case .idle: ("icloud", "等待同步", t.onSurfaceVariant)
        case .syncing: ("arrow.triangle.2.circlepath", "正在同步…", t.primary)
        case .succeeded(let date): ("checkmark.icloud", "已同步 \(date.formatted(date: .omitted, time: .shortened))", Color(hex: 0x10B981))
        case .failed: ("exclamationmark.icloud", "同步失败", t.error)
        }
        let busy = status == .syncing || status == .backingUp
        return HStack(spacing: 4) {
            Button { page = .settings } label: {
                Label(text, systemImage: icon)
                    .font(.callout)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开同步设置")
            if let syncNow, status != .disabled, status != .awaitingConfirmation {
                Button(action: syncNow) {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(busy)
                .help("立即同步（⌘R）")
                .accessibilityLabel("立即同步")
                .padding(.trailing, 6)
            }
        }
        .padding(8)
    }
}

extension AppModel.Page {
    /// 侧栏图标方块的颜色，每页一种。
    var tint: Color {
        switch self {
        case .tasks: .blue
        case .habits: .green
        case .capture: .orange
        case .overview: .indigo
        case .focus: .red
        case .archive: .brown
        case .settings: .gray
        }
    }
}
