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
    @Environment(\.palette) private var t

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
                        Label(page.title, systemImage: page.systemImage).tag(page)
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

    /// 头像与昵称，点击编辑个人资料。
    private func profileHeader(_ profile: ProfileStore) -> some View {
        Button(action: editProfile) {
            HStack(spacing: 10) {
                ProfileAvatar(store: profile, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(profile.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(Self.greeting(Date())).font(.caption).foregroundStyle(t.onSurfaceVariant)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
