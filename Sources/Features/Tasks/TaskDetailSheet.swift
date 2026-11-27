import SwiftUI
import Shared

/// 任务详情（与 iOS / 安卓相同）：只读查看时间进度、备注和子任务；子任务可以直接勾选、添加。
/// 修改标题、时间、分类等仍在编辑窗口中进行。正在专注计时的任务只能查看。
struct TaskDetailSheet: View {
    let taskId: String
    /// 从任务页取最新的任务（完成、同步后自动更新）。
    let task: (String) -> TaskItem?
    let category: (String?) -> CategoryItem?
    let commands: TaskCommands
    var onEdit: () -> Void
    var onAddToCalendar: () -> Void = {}
    var onShare: () -> Void
    var onClose: () -> Void

    @State private var draft: TaskDraft?
    @State private var newSubtask = ""
    @State private var errorMessage: String?
    @AppStorage(TaskDisplaySettings.forwardProgressKey) private var forwardProgress = false
    @AppStorage(TaskDisplaySettings.detailedRemainingKey) private var detailedRemaining = true
    @Environment(\.focusTimer) private var focusTimer
    @Environment(\.palette) private var t

    private var isLocked: Bool {
        guard let running = focusTimer?.running else { return false }
        return !running.isHabit && running.targetId == taskId
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item = task(taskId), let draft {
                    content(item, draft: draft)
                } else {
                    ContentUnavailableView("任务已不存在", systemImage: "questionmark.circle",
                                           description: Text("可能已在其他设备上删除。"))
                }
            }
            .navigationTitle("任务详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭", action: onClose) }
                if let item = task(taskId) {
                    ToolbarItem(placement: .primaryAction) {
                        Button(item.isStarred ? "取消标星" : "标星", systemImage: item.isStarred ? "star.fill" : "star") {
                            run { try commands.setStarred(taskId, !item.isStarred) }
                        }
                        .help(item.isStarred ? "取消标星" : "标星（置顶到列表前面）")
                        .disabled(isLocked)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("复制分享链接", systemImage: "link", action: onShare)
                            Button("添加到日历", systemImage: "calendar.badge.plus", action: onAddToCalendar)
                                .disabled(item.dueAt == nil)
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .help("复制分享链接或添加到日历")
                    }
                    if !item.isAbandoned {
                        ToolbarItem(placement: .primaryAction) {
                            Button(item.isCompleted ? "取消完成" : "完成",
                                   systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                                run { try commands.toggleComplete(taskId) }
                            }
                            .disabled(isLocked && !item.isCompleted)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("编辑", action: onEdit).disabled(isLocked)
                    }
                }
            }
        }
        .frame(width: 480, height: 600)
        .onAppear(perform: reload)
        .onChange(of: task(taskId)?.updatedAt) { reload() }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(_ item: TaskItem, draft: TaskDraft) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let status = TaskStatus.indicator(item, now: now)
            Form {
                if isLocked {
                    Section {
                        Label("正在专注这个任务，结束专注后才能修改", systemImage: "lock.fill").foregroundStyle(.secondary)
                    }
                }
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if item.isStarred { Image(systemName: "star.fill").foregroundStyle(status.solid(t)) }
                        Text(item.title)
                            .font(.title3.weight(.bold))
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        if let category = category(item.categoryId) { CategoryChip(category: category) }
                    }
                    HStack(spacing: 6) {
                        Circle().fill(status.solid(t)).frame(width: 8, height: 8)
                        Text(status.title)
                        let remaining = TaskStatus.remainingText(item, now: now, detailed: detailedRemaining)
                        if !remaining.isEmpty { Text("· \(remaining)").foregroundStyle(.secondary) }
                    }
                    .font(.callout)
                }
                Section("时间") {
                    LabeledContent("开始", value: item.startAt.map(Self.format) ?? String(localized: "未设置"))
                    LabeledContent("截止", value: item.dueAt.map(Self.format) ?? String(localized: "未设置"))
                    if let done = item.completedAt, item.isCompleted {
                        LabeledContent("完成于", value: Self.format(done))
                    }
                    if item.state == .active, item.dueAt != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            let progress = TaskStatus.displayedProgress(item, now: now, forward: forwardProgress)
                            ProgressView(value: min(max(progress, 0), 1))
                                .tint(status.solid(t))
                            Text(forwardProgress ? "已过去 \(Int((progress * 100).rounded()))% 的时间" : "还剩 \(Int((progress * 100).rounded()))% 的时间")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section("备注") {
                    if item.note.isEmpty {
                        Text("无备注").foregroundStyle(.secondary)
                    } else {
                        Text(item.note).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Section {
                    if draft.subtasks.isEmpty {
                        Text("还没有子任务").foregroundStyle(.secondary)
                    }
                    ForEach(draft.subtasks) { subtask in
                        Toggle(isOn: Binding(get: { subtask.isCompleted }, set: { setSubtask(subtask.id, completed: $0) })) {
                            Text(subtask.content)
                                .strikethrough(subtask.isCompleted)
                                .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                        }
                        .toggleStyle(.checkbox)
                    }
                    TextField("添加子任务", text: $newSubtask, prompt: Text("添加子任务，回车确认"))
                        .labelsHidden()
                        .onSubmit(addSubtask)
                } header: {
                    let done = draft.subtasks.filter(\.isCompleted).count
                    Text(draft.subtasks.isEmpty ? "子任务" : "子任务（已完成 \(done) / \(draft.subtasks.count)）")
                }
                .disabled(isLocked)
                if item.state == .active {
                    // 详情里没有未保存的修改，开始专注后直接关闭，只留下计时窗。
                    FocusStartSection(targetId: item.id, isHabit: false, onStarted: onClose)
                }
            }
            .formStyle(.grouped)
        }
    }

    static func format(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().weekday(.abbreviated).hour().minute())
    }

    private func reload() { draft = commands.draft(for: taskId) }

    private func setSubtask(_ id: String, completed: Bool) {
        guard var current = commands.draft(for: taskId), let index = current.subtasks.firstIndex(where: { $0.id == id }) else { return }
        current.subtasks[index].isCompleted = completed
        save(current)
    }

    private func addSubtask() {
        let content = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, var current = commands.draft(for: taskId) else { return }
        current.subtasks.append(.init(id: PlatformIdentity.shared.doNewId(), content: content, isCompleted: false))
        newSubtask = ""
        save(current)
    }

    private func save(_ updated: TaskDraft) {
        run { try commands.save(updated) }
        reload()
    }

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = error.localizedDescription }
    }
}
