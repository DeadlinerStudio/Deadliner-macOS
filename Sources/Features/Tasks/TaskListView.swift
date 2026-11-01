import SwiftUI

/// 任务页：工具栏（标题、排序、新建、系统搜索框）+ 顶部氛围光 + 自动分列的卡片网格（不出现横向滚动），
/// 右下角珊瑚色玻璃「+」。
struct TaskListView: View {
    @Bindable var store: TaskListStore
    let commands: TaskCommands
    let categoryCommands: CategoryCommands
    /// 同步未启用时，空列表上显示「配置同步」入口。
    var onSetupSync: (() -> Void)?

    @State private var pendingDelete: TaskItem?
    @State private var errorMessage: String?
    @AppStorage(CardLayout.storageKey) private var layoutRaw = CardLayout.single.rawValue
    @Environment(\.palette) private var t

    /// 氛围光颜色：有逾期任务时为 Error，有 24 小时内到期的为 Tertiary，否则为主色。
    static func tone(for tasks: [TaskItem], now: Date, palette: DeadlinerPalette) -> Color {
        let statuses = tasks.filter { $0.state == .active }.map { TaskStatus.indicator($0, now: now) }
        if statuses.contains(.passed) { return palette.error }
        if statuses.contains(.near) { return palette.tertiary }
        return palette.primary
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            TaskListContent(
                tasks: store.visibleTasks,
                totalCount: store.tasks.count,
                categories: store.categories,
                isLoading: store.isLoading,
                errorMessage: store.errorMessage,
                searchText: store.searchText,
                now: context.date,
                actionsFor: actions(for:),
                onSetupSync: onSetupSync,
                layout: CardLayout(rawValue: layoutRaw) ?? .single
            )
            .topAtmosphere(Self.tone(for: store.visibleTasks, now: context.date, palette: t))
        }
        .navigationTitle("任务")
        .navigationSubtitle(store.searchText.isEmpty ? "\(store.tasks.count) 个任务" : "\(store.visibleTasks.count) / \(store.tasks.count) 个任务")
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索任务")
        .searchFocusOnRequest()
        .toolbar {
            ToolbarItem {
                Picker("显示方式", selection: $layoutRaw) {
                    ForEach(CardLayout.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .help("显示方式")
            }
            ToolbarItem {
                Menu {
                    Picker("排序", selection: $store.sortOrder) {
                        ForEach(TaskListStore.SortOrder.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("排序", systemImage: "arrow.up.arrow.down")
                }
                .help("排序")
            }
            ToolbarItem {
                Button("新建任务", systemImage: "plus") { store.editor = .init(draft: TaskDraft()) }
                    .help("新建任务（⌘N）")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            AccentFab(label: "新建任务") { store.editor = .init(draft: TaskDraft()) }
                .padding(28)
        }
        .sheet(item: $store.editor) { request in
            TaskEditorSheet(commands: commands, categoryCommands: categoryCommands, draft: request.draft) {
                store.editor = nil
            }
            .deadlinerTheme()
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
    var searchText = ""
    let now: Date
    var actionsFor: ((TaskItem) -> TaskCard.Actions)?
    var onSetupSync: (() -> Void)?
    var layout: CardLayout = .single
    @Environment(\.palette) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    LazyVGrid(columns: layout.columns, spacing: MiuixCard.gap) {
                        ForEach(tasks) { task in
                            TaskCard(
                                task: task,
                                category: task.categoryId.flatMap { categories[$0] },
                                now: now,
                                actions: actionsFor?(task)
                            )
                        }
                    }
                    .readableWidth(layout.maxContentWidth)
                    .environment(\.cardLayout, layout)
                    .transaction(value: layout) { $0.animation = nil }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
            Text(searchText.isEmpty ? "还没有任务。点右下角的 + 新建，或配置同步后从手机拉取。" : "没有找到匹配的任务")
                .font(.callout)
            if searchText.isEmpty, let onSetupSync {
                Button("配置同步", action: onSetupSync)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
            }
        }
        .foregroundStyle(t.onSurfaceVariant)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// ⌘F：让当前页面的系统搜索框获得焦点（macOS 15 起支持；更早的系统由用户点击搜索框）。
private struct SearchFocusOnRequest: ViewModifier {
    @Environment(\.searchFocusRequest) private var request
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .searchFocused($focused)
                .onChange(of: request) { focused = true }
        } else {
            content
        }
    }
}

extension View {
    func searchFocusOnRequest() -> some View { modifier(SearchFocusOnRequest()) }
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
