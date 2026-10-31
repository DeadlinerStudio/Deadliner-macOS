import SwiftUI

/// MIUIX 风格窄侧栏（宽 208）：无分割线，选中项为圆角胶囊。
struct Sidebar: View {
    @Binding var page: AppModel.Page
    /// 底部的同步状态；为 nil 时不显示。
    var syncStatus: SyncController.Status?
    @Environment(\.palette) private var t

    static let width: CGFloat = 208

    /// 直接读取包内图标，不依赖 LaunchServices 是否已登记本应用。
    static let appIcon: NSImage = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage

    private struct Item: Identifiable {
        let page: AppModel.Page
        let title: String
        let systemImage: String
        var id: AppModel.Page { page }
    }

    private let groups: [[Item]] = [
        [Item(page: .tasks, title: "任务", systemImage: "checklist"),
         Item(page: .habits, title: "习惯", systemImage: "target")],
        [Item(page: .focus, title: "专注", systemImage: "timer"),
         Item(page: .archive, title: "存档", systemImage: "archivebox")],
        [Item(page: .settings, title: "设置", systemImage: "gearshape")],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: Self.appIcon)
                    .resizable()
                    .frame(width: 28, height: 28)
                Text("Deadliner")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(t.onSurface)
            }
            .padding(.horizontal, 10)
            .padding(.top, 44) // 留出窗口左上角红绿灯的位置
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(groups[index]) { item in row(item) }
                    }
                }
            }
            Spacer()
            if let syncStatus { syncFooter(syncStatus) }
        }
        .padding(.horizontal, 12)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(t.pageBg)
    }

    private func syncFooter(_ status: SyncController.Status) -> some View {
        let (icon, text, tint): (String, String, Color) = switch status {
        case .disabled: ("icloud.slash", "未启用同步", t.onSurfaceVariant)
        case .idle: ("icloud", "等待同步", t.onSurfaceVariant)
        case .syncing: ("arrow.triangle.2.circlepath", "正在同步…", t.primary)
        case .backingUp: ("arrow.down.doc", "正在备份云端…", t.primary)
        case .awaitingConfirmation: ("questionmark.circle", "等待确认", Color(hex: 0xF59E0B))
        case .succeeded(let date): ("checkmark.icloud", "已同步 \(date.formatted(date: .omitted, time: .shortened))", Color(hex: 0x10B981))
        case .failed: ("exclamationmark.icloud", "同步失败", t.error)
        }
        return Button { page = .settings } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(t.groupBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("打开同步设置")
        .padding(.bottom, 16)
    }

    private func row(_ item: Item) -> some View {
        let active = page == item.page
        return Button { page = item.page } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: active ? .semibold : .regular))
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 14.5, weight: active ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(active ? t.primary : t.onSurface)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(active ? t.primary.opacity(t.isDark ? 0.16 : 0.12) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
