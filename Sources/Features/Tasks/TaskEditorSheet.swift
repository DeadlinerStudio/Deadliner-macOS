import SwiftUI
import Shared

/// 任务编辑器：系统弹窗 + 分组表单，取消 / 保存在系统按钮位置；分类选择保留 Deadliner 的彩色标签。
struct TaskEditorSheet: View {
    let commands: TaskCommands
    let categoryCommands: CategoryCommands
    var onClose: () -> Void
    /// 保存成功后调用（例如把灵感标记为已整理）。
    var onSaved: (() -> Void)?

    @State private var draft: TaskDraft
    @State private var categories: [CategoryItem] = []
    @State private var newSubtask = ""
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var managingCategories = false

    init(commands: TaskCommands, categoryCommands: CategoryCommands, draft: TaskDraft, onSaved: (() -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self.onSaved = onSaved
        self.commands = commands
        self.categoryCommands = categoryCommands
        self.onClose = onClose
        _draft = State(initialValue: draft)
    }

    private var isEditing: Bool { draft.id != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务名称", text: $draft.title, prompt: Text("任务名称"))
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .font(.title3.weight(.semibold))
                    TextField("备注（可选）", text: $draft.note, prompt: Text("备注"), axis: .vertical)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .lineLimit(3...6)
                }

                Section("时间") {
                    OptionalDateRow(title: "开始时间", date: $draft.startAt, defaultValue: Self.defaultStart)
                    OptionalDateRow(title: "截止时间", date: $draft.dueAt, defaultValue: Self.defaultDue)
                    Toggle("标星", isOn: $draft.isStarred)
                }

                if let id = draft.id, draft.isActive {
                    FocusStartSection(targetId: id, isHabit: false)
                }

                Section {
                    FlowLayout(spacing: 8) {
                        CategoryChoiceChip(title: "无分类", selected: draft.categoryId == nil) { draft.categoryId = nil }
                        ForEach(categories) { category in
                            CategoryChoiceChip(title: category.name, icon: CategoryIcons.symbol(for: category.iconKey),
                                               color: Color(hexString: category.colorHex), selected: draft.categoryId == category.id) {
                                draft.categoryId = category.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("分类")
                        Spacer()
                        Button("管理分类…") { managingCategories = true }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }

                Section("子任务") {
                    ForEach(Array(draft.subtasks.enumerated()), id: \.element.id) { index, _ in
                        SubtaskRow(
                            subtask: $draft.subtasks[index],
                            canMoveUp: index > 0,
                            canMoveDown: index < draft.subtasks.count - 1,
                            moveUp: { draft.subtasks.swapAt(index, index - 1) },
                            moveDown: { draft.subtasks.swapAt(index, index + 1) },
                            remove: { draft.subtasks.remove(at: index) }
                        )
                    }
                    TextField("添加子任务", text: $newSubtask, prompt: Text("添加子任务，回车确认"))
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .onSubmit(addSubtask)
                }

                if isEditing {
                    Section {
                        Button("删除任务", role: .destructive) { confirmDelete = true }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "编辑任务" : "新建任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        addSubtask()
                        perform { try commands.save(draft); onSaved?() }
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .frame(width: 520, height: 640)
        .onAppear { categories = categoryCommands.list() }
        .sheet(isPresented: $managingCategories, onDismiss: { categories = categoryCommands.list() }) {
            CategoryManagerSheet(commands: categoryCommands) { managingCategories = false }
                .deadlinerTheme()
        }
        .confirmationDialog("确定要删除这个任务吗？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { perform { try commands.delete(draft.id!) } }
        } message: {
            Text("启用同步后，删除也会同步到手机。")
        }
    }

    private static func defaultStart() -> Date {
        Calendar.current.date(bySetting: .minute, value: 0, of: Date()) ?? Date()
    }

    private static func defaultDue() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow) ?? tomorrow
    }

    private func addSubtask() {
        let content = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        draft.subtasks.append(.init(id: PlatformIdentity.shared.doNewId(), content: content, isCompleted: false))
        newSubtask = ""
    }

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 可选日期：一行标题加 Deadliner 日期选择，面板里可选「不设时间」。
struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?
    var components: DeadlinerDatePickerMode = .dateAndTime
    var defaultValue: () -> Date

    var body: some View {
        LabeledContent(title) {
            DeadlinerDatePicker(selection: $date, components: components, defaultValue: defaultValue)
        }
    }
}

/// 子任务行：勾选、内容、上移 / 下移 / 删除。
private struct SubtaskRow: View {
    @Binding var subtask: TaskDraft.Subtask
    let canMoveUp: Bool
    let canMoveDown: Bool
    var moveUp: () -> Void
    var moveDown: () -> Void
    var remove: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        HStack(spacing: 8) {
            Button { subtask.isCompleted.toggle() } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isCompleted ? t.completedCheck : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "标记未完成" : "标记完成")
            TextField("子任务", text: $subtask.content)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .textFieldStyle(.plain)
                .strikethrough(subtask.isCompleted)
            Button(action: moveUp) { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp).help("上移")
            Button(action: moveDown) { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown).help("下移")
            Button(action: remove) { Image(systemName: "xmark") }
                .help("删除子任务")
        }
        .buttonStyle(.borderless)
    }
}

/// 分类选择标签：彩色胶囊，选中时填充分类色。
struct CategoryChoiceChip: View {
    let title: String
    var icon: String?
    var color: Color?
    let selected: Bool
    var action: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        let tint = color ?? t.onSurfaceVariant
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption.weight(.semibold)) }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(selected ? Color.white : tint)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(selected ? tint : tint.opacity(t.isDark ? 0.22 : 0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
