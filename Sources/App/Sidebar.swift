import SwiftUI

/// MIUIX 风格窄侧栏（宽 208）：无分割线，选中项为圆角胶囊。
struct Sidebar: View {
    @Binding var page: AppModel.Page
    @Environment(\.miuix) private var t

    static let width: CGFloat = 208

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
                Image(nsImage: NSApp.applicationIconImage)
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
        }
        .padding(.horizontal, 12)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(t.pageBg)
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
