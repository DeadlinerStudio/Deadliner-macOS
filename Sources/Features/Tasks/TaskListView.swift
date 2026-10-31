import SwiftUI

/// 任务页：大标题 + 搜索框 + 自动分列的卡片网格（不出现横向滚动）。
struct TaskListView: View {
    @Bindable var store: TaskListStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            TaskListContent(
                tasks: store.visibleTasks,
                totalCount: store.tasks.count,
                categories: store.categories,
                isLoading: store.isLoading,
                errorMessage: store.errorMessage,
                searchText: $store.searchText,
                sortOrder: $store.sortOrder,
                now: context.date
            )
        }
    }
}

/// 不依赖 Core 的页面主体，便于预览和截图测试。
struct TaskListContent: View {
    let tasks: [TaskItem]
    let totalCount: Int
    let categories: [String: CategoryItem]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var searchText: String
    @Binding var sortOrder: TaskListStore.SortOrder
    let now: Date
    @Environment(\.miuix) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let errorMessage {
                Text("读取任务失败：\(errorMessage)")
                    .font(.callout)
                    .foregroundStyle(t.error)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
            }
            if tasks.isEmpty && !isLoading {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: MiuixCard.minColumnWidth), spacing: MiuixCard.gap)],
                        spacing: MiuixCard.gap
                    ) {
                        ForEach(tasks) { task in
                            TaskCard(task: task, category: task.categoryId.flatMap { categories[$0] }, now: now)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.pageBg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Deadliner")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(t.onSurface)
                Text(searchText.isEmpty ? "\(totalCount) 个任务" : "\(tasks.count) / \(totalCount) 个任务")
                    .font(.system(size: 13))
                    .foregroundStyle(t.onSurfaceVariant)
                Spacer()
                Picker("排序", selection: $sortOrder) {
                    ForEach(TaskListStore.SortOrder.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            SearchPill(text: $searchText, placeholder: "搜索任务")
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
            Text(searchText.isEmpty ? "还没有任务。配置同步后会从手机拉取。" : "没有找到匹配的任务")
                .font(.callout)
        }
        .foregroundStyle(t.onSurfaceVariant)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// MIUIX 搜索框：胶囊形、浅色底。
struct SearchPill: View {
    @Binding var text: String
    let placeholder: String
    @Environment(\.miuix) private var t
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.onSurfaceVariant)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(t.onSurface)
                .focused($focused)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(t.searchBg, in: Capsule())
        .overlay(Capsule().strokeBorder(t.primary.opacity(focused ? 0.35 : 0), lineWidth: 2))
    }
}
