import SwiftUI

/// 任务页：工具栏（标题、排序、新建、系统搜索框）+ 顶部氛围光 + 自动分列的卡片网格（不出现横向滚动）。
struct TaskListView: View {
    @Bindable var store: TaskListStore
    let commands: TaskCommands
    let categoryCommands: CategoryCommands
    /// 同步未启用时，空列表上显示「配置同步」入口。
    var onSetupSync: (() -> Void)?
    /// 搜索时归档中匹配的任务数，以及跳到归档页的动作。
    var archiveMatches: (String) -> Int = { _ in 0 }
    var onShowArchive: ((String) -> Void)?

    @State private var pendingDelete: TaskItem?
    /// 多选：nil 表示不在多选状态。
    @State private var selection: Set<String>?
    @State private var pendingBatchDelete = false
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
                layout: CardLayout(rawValue: layoutRaw) ?? .single,
                selection: selection,
                isFiltered: store.categoryFilter != nil,
                archiveMatches: archiveMatches(store.searchText),
                onShowArchive: onShowArchive.map { show in { show(store.searchText) } }
            )
            .topAtmosphere(Self.tone(for: store.visibleTasks, now: context.date, palette: t))
        }
        .navigationTitle("任务")
        .navigationSubtitle(subtitle)
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
                    Picker("分类", selection: $store.categoryFilter) {
                        Text("全部分类").tag(String?.none)
                        Divider()
                        ForEach(store.categories.values.sorted { $0.sortOrder < $1.sortOrder }) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                        Text("未分类").tag(Optional(TaskListStore.uncategorized))
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("分类筛选", systemImage: store.categoryFilter == nil
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .help("按分类筛选")
            }
            ToolbarItem {
                Button(selection == nil ? "选择" : "完成选择", systemImage: selection == nil ? "checkmark.circle" : "checkmark.circle.fill") {
                    selection = selection == nil ? [] : nil
                }
                .help("多选任务（也可以按住 ⌘ 点按卡片）")
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
        .overlay(alignment: .bottom) {
            if let selection { batchBar(selection) }
        }
        .onExitCommand { if selection != nil { selection = nil } }
        .onChange(of: store.visibleTasks.map(\.id)) { _, ids in
            // 同步或筛选后，去掉已经不在列表中的选中项。
            if let current = selection { selection = current.intersection(ids) }
        }
        .confirmationDialog("确定要删除选中的 \(selection?.count ?? 0) 个任务吗？", isPresented: $pendingBatchDelete) {
            Button("删除", role: .destructive) {
                batch { try commands.delete($0.id) }
            }
        } message: {
            Text("启用同步后，删除也会同步到手机。")
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
            delete: { pendingDelete = task },
            postpone: { amount, hours in run { try commands.postpone(task.id, amount: amount, inHours: hours) } },
            select: {
                var current = selection ?? []
                if current.contains(task.id) { current.remove(task.id) } else { current.insert(task.id) }
                selection = current
            }
        )
    }

    private var subtitle: String {
        if let selection { return "已选 \(selection.count) 个" }
        let filtered = !store.searchText.isEmpty || store.categoryFilter != nil
        return filtered ? "\(store.visibleTasks.count) / \(store.tasks.count) 个任务" : "\(store.tasks.count) 个任务"
    }

    private var selectedTasks: [TaskItem] {
        guard let selection else { return [] }
        return store.visibleTasks.filter { selection.contains($0.id) }
    }

    /// 底部的批量操作栏。完成与归档只作用于状态允许的任务（由 Core 状态机判断）。
    private func batchBar(_ selection: Set<String>) -> some View {
        let tasks = selectedTasks
        let completable = tasks.filter { $0.state == .active }
        let archivable = tasks.filter { TaskCommands.canApply(.markArchive, to: $0.state) }
        let allSelected = !store.visibleTasks.isEmpty && selection.count == store.visibleTasks.count
        return HStack(spacing: 10) {
            Button(allSelected ? "全不选" : "全选") {
                self.selection = allSelected ? [] : Set(store.visibleTasks.map(\.id))
            }
            Divider().frame(height: 18)
            Button("完成\(completable.isEmpty ? "" : " \(completable.count)")", systemImage: "checkmark") {
                batch(completable) { try commands.toggleComplete($0.id) }
            }
            .disabled(completable.isEmpty)
            Button("归档\(archivable.isEmpty ? "" : " \(archivable.count)")", systemImage: "archivebox") {
                batch(archivable) { try commands.archive($0.id) }
            }
            .disabled(archivable.isEmpty)
            Button("删除", systemImage: "trash", role: .destructive) { pendingBatchDelete = true }
                .disabled(tasks.isEmpty)
            Divider().frame(height: 18)
            Button("取消") { self.selection = nil }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .deadlinerGlass(in: Capsule())
        .padding(.bottom, 24)
    }

    /// 对选中的任务逐个执行；遇到错误时停下并提示，已完成的不回滚。完成后退出多选。
    private func batch(_ tasks: [TaskItem]? = nil, _ body: (TaskItem) throws -> Void) {
        for task in tasks ?? selectedTasks {
            do { try body(task) } catch {
                errorMessage = "「\(task.title)」：\(error.localizedDescription)"
                break
            }
        }
        selection = nil
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
    var selection: Set<String>?
    /// 有分类筛选时，空列表显示「没有找到」而不是新手提示。
    var isFiltered = false
    var archiveMatches = 0
    var onShowArchive: (() -> Void)?
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
                    .overlay(alignment: .bottom) { archiveHint.padding(.bottom, 60) }
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: layout.columns, spacing: MiuixCard.gap) {
                        ForEach(tasks) { task in
                            TaskCard(
                                task: task,
                                category: task.categoryId.flatMap { categories[$0] },
                                now: now,
                                actions: actionsFor?(task),
                                selected: selection.map { $0.contains(task.id) }
                            )
                        }
                    }
                    .readableWidth(layout.maxContentWidth)
                    .safeAreaInset(edge: .bottom) { archiveHint.padding(.top, 14) }
                    .environment(\.cardSweepKey, Self.sweepKey(tasks, layout: layout))
                    .transaction(value: layout) { $0.animation = nil }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 列表的签名：排列方式、顺序，以及每个任务影响进度的字段。只随数据变化，不随时间流逝变化。
    static func sweepKey(_ tasks: [TaskItem], layout: CardLayout) -> String {
        var hasher = Hasher()
        for task in tasks {
            hasher.combine(task.id)
            hasher.combine(task.state)
            hasher.combine(task.startAt)
            hasher.combine(task.dueAt)
            hasher.combine(task.updatedAt)
        }
        return "\(layout.rawValue)-\(hasher.finalize())"
    }

    @ViewBuilder
    private var archiveHint: some View {
        if !searchText.isEmpty, archiveMatches > 0, let onShowArchive {
            Button(action: onShowArchive) {
                Label("归档中还有 \(archiveMatches) 个匹配的任务", systemImage: "archivebox")
                    .font(.callout)
            }
            .buttonStyle(.link)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
            Text(searchText.isEmpty && !isFiltered ? "暂无任务" : "没有找到匹配的任务")
                .font(.callout)
            if searchText.isEmpty, !isFiltered, let onSetupSync {
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
