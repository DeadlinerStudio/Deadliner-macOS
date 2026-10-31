import SwiftUI

/// 任务页：大标题 + 搜索框 + 自动分列的卡片网格（不出现横向滚动），右下角撞色新建按钮。
struct TaskListView: View {
    @Bindable var store: TaskListStore
    let commands: TaskCommands
    let categoryCommands: CategoryCommands
    /// 同步未启用时，空列表上显示「配置同步」入口。
    var onSetupSync: (() -> Void)?

    @State private var pendingDelete: TaskItem?
    @State private var errorMessage: String?

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
                now: context.date,
                actionsFor: actions(for:),
                onSetupSync: onSetupSync
            )
        }
        .overlay(alignment: .bottomTrailing) {
            AccentFab(label: "新建任务") { store.editor = .init(draft: TaskDraft()) }
                .padding(28)
        }
        .sheet(item: $store.editor) { request in
            TaskEditorSheet(commands: commands, categoryCommands: categoryCommands, draft: request.draft) {
                store.editor = nil
            }
            .miuixTheme()
        }
        .confirmationDialog("确定要删除「\(pendingDelete?.title ?? "")」吗？", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let task = pendingDelete { run { try commands.delete(task.id) } }
                pendingDelete = nil
            }
        } message: {
            Text("启用同步后，删除也会同步到手机。")
        }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func actions(for task: TaskItem) -> TaskCard.Actions {
        TaskCard.Actions(
            toggleComplete: { run { try commands.toggleComplete(task.id) } },
            open: {
                if let draft = commands.draft(for: task.id) { store.editor = .init(draft: draft) }
            },
            toggleStar: { run { try commands.setStarred(task.id, !task.isStarred) } },
            toggleGiveUp: { run { try commands.toggleGiveUp(task.id) } },
            archive: { run { try commands.archive(task.id) } },
            delete: { pendingDelete = task }
        )
    }

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = error.localizedDescription }
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
    var actionsFor: ((TaskItem) -> TaskCard.Actions)?
    var onSetupSync: (() -> Void)?
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
                            TaskCard(
                                task: task,
                                category: task.categoryId.flatMap { categories[$0] },
                                now: now,
                                actions: actionsFor?(task)
                            )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 100)
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
            Text(searchText.isEmpty ? "还没有任务。点右下角的 + 新建，或配置同步后从手机拉取。" : "没有找到匹配的任务")
                .font(.callout)
            if searchText.isEmpty, let onSetupSync {
                MiuixButton(title: "配置同步", kind: .primary, action: onSetupSync)
                    .padding(.top, 6)
            }
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
    @Environment(\.searchFocusRequest) private var focusRequest
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
        .onChange(of: focusRequest) { focused = true }
    }
}

private struct SearchFocusRequestKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// ⌘F 计数，变化时搜索框获得焦点。
    var searchFocusRequest: Int {
        get { self[SearchFocusRequestKey.self] }
        set { self[SearchFocusRequestKey.self] = newValue }
    }
}
