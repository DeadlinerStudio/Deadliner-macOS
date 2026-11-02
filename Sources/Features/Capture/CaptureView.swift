import SwiftUI

/// 灵感页：先把想法记下来，之后再整理成任务或习惯（与 Android / iOS 的「灵感」相同，不含 AI 整理）。
struct CaptureView: View {
    @Bindable var store: CaptureStore
    let taskCommands: TaskCommands
    let categoryCommands: CategoryCommands
    let habitCommands: HabitCommands
    let categories: [String: CategoryItem]

    @State private var draft = ""
    @State private var selection: Set<String>?
    @State private var editing: CaptureStore.Idea?
    @State private var organizing: Organize?
    @State private var pendingDelete: [String] = []
    @AppStorage(CardLayout.storageKey) private var layoutRaw = CardLayout.single.rawValue
    @FocusState private var composerFocused: Bool
    @Environment(\.palette) private var t

    /// 正在整理的灵感：打开任务或习惯编辑器，保存后把灵感标记为已整理。
    struct Organize: Identifiable {
        enum Target { case task, habit }
        let id = UUID()
        let ideaId: String
        let text: String
        let target: Target
    }

    var body: some View {
        CaptureContent(
            items: store.visibleItems,
            searchText: store.searchText,
            draft: $draft,
            composerFocused: $composerFocused,
            selection: selection,
            layout: CardLayout(rawValue: layoutRaw) ?? .single,
            onSave: save,
            onOpen: { editing = $0 },
            onOrganize: { idea, target in organizing = Organize(ideaId: idea.id, text: idea.text, target: target) },
            onDelete: { pendingDelete = [$0.id] },
            onToggle: toggle
        )
        .topAtmosphere(t.tertiary)
        .navigationTitle("灵感")
        .navigationSubtitle(selection.map { "已选 \($0.count) 条" } ?? "\(store.items.count) 条未整理")
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索灵感")
        .searchFocusOnRequest()
        .toolbar {
            ToolbarItem {
                Button(selection == nil ? "选择" : "完成选择", systemImage: selection == nil ? "checkmark.circle" : "checkmark.circle.fill") {
                    selection = selection == nil ? [] : nil
                }
                .help("多选后可以合并整理或批量删除")
            }
        }
        .overlay(alignment: .bottom) {
            if let selection { batchBar(selection) }
        }
        .onExitCommand { if selection != nil { selection = nil } }
        .onAppear { store.refresh() }
        .sheet(item: $editing) { idea in
            CaptureEditSheet(idea: idea) { text in
                store.update(idea.id, text: text)
                editing = nil
            } onDelete: {
                editing = nil
                pendingDelete = [idea.id]
            } onCancel: {
                editing = nil
            }
            .deadlinerTheme()
        }
        .sheet(item: $organizing) { request in
            organizeSheet(request).deadlinerTheme()
        }
        .confirmationDialog(pendingDelete.count > 1 ? "删除选中的 \(pendingDelete.count) 条灵感？" : "删除这条灵感？",
                            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
            Button("删除", role: .destructive) {
                store.delete(pendingDelete)
                pendingDelete = []
                selection = nil
            }
        } message: {
            Text("此操作不可撤销。启用同步后，删除也会同步到其他设备。")
        }
    }

    private func save() {
        if store.create(draft) != nil { draft = "" }
    }

    private func toggle(_ idea: CaptureStore.Idea) {
        var current = selection ?? []
        if current.contains(idea.id) { current.remove(idea.id) } else { current.insert(idea.id) }
        selection = current
    }

    @ViewBuilder
    private func organizeSheet(_ request: Organize) -> some View {
        let parts = CaptureStore.titleAndNote(request.text)
        switch request.target {
        case .task:
            let taskDraft: TaskDraft = {
                var d = TaskDraft()
                d.title = parts.title
                d.note = parts.note
                return d
            }()
            TaskEditorSheet(commands: taskCommands, categoryCommands: categoryCommands, draft: taskDraft,
                            onSaved: { store.markConsumed(request.ideaId) }) { organizing = nil }
        case .habit:
            let habitDraft: HabitDraft = {
                var d = HabitDraft()
                d.name = parts.title
                d.note = parts.note
                return d
            }()
            HabitEditorSheet(commands: habitCommands, categories: categories.values.sorted { $0.sortOrder < $1.sortOrder },
                             draft: habitDraft, onSaved: { store.markConsumed(request.ideaId) }) { organizing = nil }
        }
    }

    /// 底部的多选操作：合并整理（先合并成一条，再整理成任务或习惯）与删除。
    private func batchBar(_ selection: Set<String>) -> some View {
        HStack(spacing: 10) {
            Button(selection.count == store.visibleItems.count && !selection.isEmpty ? "全不选" : "全选") {
                self.selection = selection.count == store.visibleItems.count ? [] : Set(store.visibleItems.map(\.id))
            }
            Divider().frame(height: 18)
            Menu {
                Button("整理成任务", systemImage: "checklist") { mergeAndOrganize(.task) }
                Button("整理成习惯", systemImage: "target") { mergeAndOrganize(.habit) }
                Divider()
                Button("只合并", systemImage: "square.stack") { _ = store.merge(selection); self.selection = nil }
                    .disabled(selection.count < 2)
            } label: {
                Label(selection.count > 1 ? "合并整理 \(selection.count)" : "整理", systemImage: "wand.and.stars")
            }
            .fixedSize()
            .disabled(selection.isEmpty)
            Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = Array(selection) }
                .disabled(selection.isEmpty)
            Divider().frame(height: 18)
            Button("取消") { self.selection = nil }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .deadlinerGlass(in: Capsule())
        .padding(.bottom, 24)
    }

    private func mergeAndOrganize(_ target: Organize.Target) {
        guard let selection, let merged = store.merge(selection) else { return }
        self.selection = nil
        organizing = Organize(ideaId: merged.id, text: merged.text, target: target)
    }
}

/// 不依赖 Core 的页面主体，便于截图测试。
struct CaptureContent: View {
    let items: [CaptureStore.Idea]
    var searchText = ""
    @Binding var draft: String
    var composerFocused: FocusState<Bool>.Binding
    var selection: Set<String>?
    var layout: CardLayout = .single
    var onSave: () -> Void = {}
    var onOpen: (CaptureStore.Idea) -> Void = { _ in }
    var onOrganize: (CaptureStore.Idea, CaptureView.Organize.Target) -> Void = { _, _ in }
    var onDelete: (CaptureStore.Idea) -> Void = { _ in }
    var onToggle: (CaptureStore.Idea) -> Void = { _ in }
    @Environment(\.palette) private var t

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                composer
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "lightbulb").font(.system(size: 30))
                        Text(searchText.isEmpty ? "还没有新的灵感。先写下来，之后再整理成任务或习惯。" : "没有找到匹配的灵感")
                            .font(.callout)
                    }
                    .foregroundStyle(t.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    Text("最近的灵感")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.onSurfaceVariant)
                        .padding(.leading, 4)
                    LazyVGrid(columns: layout.columns.map { var item = $0; item.alignment = .top; return item }, spacing: MiuixCard.gap) {
                        ForEach(items) { idea in
                            CaptureCard(idea: idea, selected: selection.map { $0.contains(idea.id) },
                                        onOpen: { onOpen(idea) }, onOrganize: { onOrganize(idea, $0) },
                                        onDelete: { onDelete(idea) }, onToggle: { onToggle(idea) })
                        }
                    }
                }
            }
            .readableWidth(layout.maxContentWidth)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("先记下一个想法").font(.headline)
            TextField("例如：也许可以开始每周复盘……", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .focused(composerFocused)
                .onSubmit(onSave)
            HStack {
                Text("之后再整理成任务或习惯").font(.caption).foregroundStyle(t.onSurfaceVariant)
                Spacer()
                Button("保存灵感", action: onSave)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(t.groupBg, in: RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
    }
}

/// 一条灵感：正文最多 5 行，下方显示时间；悬停时显示整理与删除。
private struct CaptureCard: View {
    let idea: CaptureStore.Idea
    var selected: Bool?
    var onOpen: () -> Void
    var onOrganize: (CaptureView.Organize.Target) -> Void
    var onDelete: () -> Void
    var onToggle: () -> Void
    @State private var hovering = false
    @Environment(\.palette) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: idea.text)
                .font(.body)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text(idea.createdAt.map { $0.formatted(.relative(presentation: .named)) } ?? "")
                    .font(.caption)
                    .foregroundStyle(t.onSurfaceVariant)
                Spacer()
                if hovering && selected == nil {
                    Menu {
                        Button("整理成任务", systemImage: "checklist") { onOrganize(.task) }
                        Button("整理成习惯", systemImage: "target") { onOrganize(.habit) }
                    } label: {
                        Label("整理", systemImage: "wand.and.stars").font(.caption.weight(.semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("删除")
                }
            }
            .frame(height: 20)
        }
        .padding(16)
        .background(t.tertiary.opacity(0.12), in: RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .overlay {
            if let selected {
                RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous)
                    .strokeBorder(selected ? t.primary : t.onSurface.opacity(0.15), lineWidth: selected ? 2.5 : 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture {
            if selected != nil || NSEvent.modifierFlags.contains(.command) { onToggle() } else { onOpen() }
        }
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: onOpen)
            Button("整理成任务", systemImage: "checklist") { onOrganize(.task) }
            Button("整理成习惯", systemImage: "target") { onOrganize(.habit) }
            Divider()
            Button("选择", systemImage: "checkmark.circle", action: onToggle)
            Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// 查看与编辑一条灵感。
private struct CaptureEditSheet: View {
    let idea: CaptureStore.Idea
    var onSave: (String) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void
    @State private var text: String

    init(idea: CaptureStore.Idea, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.idea = idea
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _text = State(initialValue: idea.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("灵感详情").font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minWidth: 420, minHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("删除", role: .destructive, action: onDelete)
                Spacer()
                Button("取消", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}
