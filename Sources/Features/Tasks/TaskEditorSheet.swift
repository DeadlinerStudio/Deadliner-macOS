import SwiftUI
import Shared

/// 任务编辑器（仿安卓底部弹出面板）：圆角 28，填充式输入框，操作按钮在底部。
struct TaskEditorSheet: View {
    let commands: TaskCommands
    let categoryCommands: CategoryCommands
    let original: TaskDraft
    var onClose: () -> Void

    @State private var draft: TaskDraft
    @State private var categories: [CategoryItem] = []
    @State private var newSubtask = ""
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var managingCategories = false
    @Environment(\.palette) private var t

    init(commands: TaskCommands, categoryCommands: CategoryCommands, draft: TaskDraft, onClose: @escaping () -> Void) {
        self.commands = commands
        self.categoryCommands = categoryCommands
        self.original = draft
        self.onClose = onClose
        _draft = State(initialValue: draft)
    }

    private var isEditing: Bool { draft.id != nil }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(t.onSurfaceVariant.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
            Text(isEditing ? "编辑任务" : "新建任务")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(t.onSurface)
                .padding(.top, 12)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MiuixTextField(placeholder: "任务标题", text: $draft.title, font: .system(size: 16, weight: .semibold))
                    MiuixTextField(placeholder: "备注", text: $draft.note, axis: .vertical)
                    timeGroup
                    categoryGroup
                    subtaskGroup
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(t.error)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 6)
            }
            bottomBar
        }
        .frame(width: 520, height: 660)
        .background(t.pageBg)
        .clipShape(RoundedRectangle(cornerRadius: MiuixRadius.dialog, style: .continuous))
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

    // MARK: - Groups

    private var timeGroup: some View {
        MiuixGroup(title: "时间") {
            dateRow("开始时间", systemImage: "play.circle", tint: t.secondary, date: $draft.startAt)
            dateRow("截止时间", systemImage: "flag", tint: t.error, date: $draft.dueAt)
            MiuixRow(title: "标星", systemImage: "star.fill", tint: Color(hex: 0xF5A623)) {
                Toggle("", isOn: $draft.isStarred).labelsHidden().toggleStyle(.miuix)
            }
        }
    }

    private func dateRow(_ title: String, systemImage: String, tint: Color, date: Binding<Date?>) -> some View {
        MiuixRow(title: title, systemImage: systemImage, tint: tint) {
            if let value = date.wrappedValue {
                DatePicker("", selection: Binding(get: { value }, set: { date.wrappedValue = $0 }), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            Toggle("", isOn: Binding(
                get: { date.wrappedValue != nil },
                set: { date.wrappedValue = $0 ? Self.defaultDate(for: title) : nil }
            ))
            .labelsHidden()
            .toggleStyle(.miuix)
        }
    }

    private static func defaultDate(for title: String) -> Date {
        let calendar = Calendar.current
        let base = title == "开始时间" ? Date() : calendar.date(byAdding: .day, value: 1, to: Date())!
        return calendar.date(bySettingHour: title == "开始时间" ? calendar.component(.hour, from: base) : 23,
                             minute: title == "开始时间" ? 0 : 59, second: 0, of: base) ?? base
    }

    private var categoryGroup: some View {
        MiuixGroup(title: "分类") {
            FlowLayout(spacing: 8) {
                choiceChip("无分类", selected: draft.categoryId == nil) { draft.categoryId = nil }
                ForEach(categories) { category in
                    choiceChip(category.name, icon: CategoryIcons.symbol(for: category.iconKey),
                               color: Color(hexString: category.colorHex), selected: draft.categoryId == category.id) {
                        draft.categoryId = category.id
                    }
                }
                Button { managingCategories = true } label: {
                    Label("管理分类", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(t.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func choiceChip(_ title: String, icon: String? = nil, color: Color? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        let tint = color ?? t.onSurfaceVariant
        return Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(selected ? Color.white : tint)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(selected ? tint : tint.opacity(t.isDark ? 0.22 : 0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var subtaskGroup: some View {
        MiuixGroup(title: "子任务") {
            ForEach(Array(draft.subtasks.enumerated()), id: \.element.id) { index, _ in
                HStack(spacing: 10) {
                    Button { draft.subtasks[index].isCompleted.toggle() } label: {
                        Image(systemName: draft.subtasks[index].isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(draft.subtasks[index].isCompleted ? t.completedCheck : t.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                    TextField("子任务", text: $draft.subtasks[index].content)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .strikethrough(draft.subtasks[index].isCompleted)
                        .foregroundStyle(t.onSurface)
                    iconButton("chevron.up", disabled: index == 0) { draft.subtasks.swapAt(index, index - 1) }
                    iconButton("chevron.down", disabled: index == draft.subtasks.count - 1) { draft.subtasks.swapAt(index, index + 1) }
                    iconButton("xmark", disabled: false) { draft.subtasks.remove(at: index) }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
            }
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(t.primary)
                TextField("添加子任务，回车确认", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit(addSubtask)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
        }
    }

    private func iconButton(_ name: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.onSurfaceVariant)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    private func addSubtask() {
        let content = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        draft.subtasks.append(.init(id: PlatformIdentity.shared.doNewId(), content: content, isCompleted: false))
        newSubtask = ""
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if isEditing {
                MiuixButton(title: "删除", kind: .destructive) { confirmDelete = true }
            }
            Spacer()
            MiuixButton(title: "取消") { onClose() }
                .keyboardShortcut(.cancelAction)
            MiuixButton(title: "保存", kind: .primary) {
                addSubtask()
                perform { try commands.save(draft) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!draft.isValid)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(t.groupBg)
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
