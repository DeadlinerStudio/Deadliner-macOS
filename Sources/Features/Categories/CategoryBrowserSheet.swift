import SwiftUI

/// 分类详情（与 iOS 的分类详情相同）：列出各分类，点开查看其中的任务与习惯。
/// 只读；可以打开任务的编辑窗口，或回到任务页只看这个分类。
struct CategoryBrowserSheet: View {
    let commands: CategoryCommands
    var onClose: () -> Void
    var openTask: (String) -> Void
    /// 任务页按分类筛选（`TaskListStore.uncategorized` 表示未分类）。
    var filterTasks: (String) -> Void

    @State private var categories: [CategoryItem] = []
    @State private var managing = false
    @Environment(\.palette) private var t

    /// nil 表示「未分类」。
    private struct Entry: Hashable { let id: String? }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(categories) { category in
                        NavigationLink(value: Entry(id: category.id)) { row(category: category) }
                    }
                    NavigationLink(value: Entry(id: nil)) { row(category: nil) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("分类")
            .navigationDestination(for: Entry.self) { entry in
                CategoryContentsView(category: entry.id.flatMap { id in categories.first { $0.id == id } },
                                     contents: commands.contents(of: entry.id),
                                     openTask: openTask,
                                     filterTasks: { filterTasks(entry.id ?? TaskListStore.uncategorized) })
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) }
                ToolbarItem(placement: .primaryAction) {
                    Button("管理分类", systemImage: "slider.horizontal.3") { managing = true }
                }
            }
        }
        .frame(width: 520, height: 600)
        .onAppear(perform: reload)
        .sheet(isPresented: $managing, onDismiss: reload) {
            CategoryManagerSheet(commands: commands) { managing = false }.deadlinerTheme()
        }
    }

    private func reload() { categories = commands.list() }

    private func row(category: CategoryItem?) -> some View {
        let contents = commands.contents(of: category?.id)
        let active = contents.tasks.filter { $0.state == .active }.count
        return HStack(spacing: 12) {
            Image(systemName: category.map { CategoryIcons.symbol(for: $0.iconKey) } ?? "tray")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(category.flatMap { Color(hexString: $0.colorHex) } ?? Color.gray, in: Circle())
            Text(category?.name ?? "未分类")
            Spacer()
            Text("\(active) 个进行中 · \(contents.tasks.count) 个任务 · \(contents.habits.count) 个习惯")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 一个分类里的任务（进行中 / 已结束）与习惯。
private struct CategoryContentsView: View {
    let category: CategoryItem?
    let contents: CategoryCommands.Contents
    var openTask: (String) -> Void
    var filterTasks: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        let now = Date()
        let active = contents.tasks.filter { $0.state == .active }
        let finished = contents.tasks.filter { $0.state != .active }
        Form {
            if contents.isEmpty {
                Section { Text("这个分类里还没有任务或习惯。").foregroundStyle(.secondary) }
            }
            if !active.isEmpty {
                Section("进行中的任务（\(active.count)）") {
                    ForEach(active) { taskRow($0, now: now) }
                }
            }
            if !contents.habits.isEmpty {
                Section("习惯（\(contents.habits.count)）") {
                    ForEach(contents.habits) { habit in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(habit.colorHex.flatMap { Color(hexString: $0) } ?? t.primary)
                                .frame(width: 10, height: 10)
                            Text(habit.name)
                            Spacer()
                            if habit.isArchived { Text("已归档").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if !finished.isEmpty {
                Section("已结束的任务（\(finished.count)）") {
                    ForEach(finished) { taskRow($0, now: now) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category?.name ?? "未分类")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("在任务页只看这个分类", systemImage: "line.3.horizontal.decrease.circle", action: filterTasks)
            }
        }
    }

    private func taskRow(_ task: TaskItem, now: Date) -> some View {
        let status = TaskStatus.indicator(task, now: now)
        return Button { openTask(task.id) } label: {
            HStack(spacing: 10) {
                Circle().fill(status.solid(t)).frame(width: 10, height: 10)
                if task.isStarred { Image(systemName: "star.fill").font(.caption).foregroundStyle(status.solid(t)) }
                Text(task.title)
                    .foregroundStyle(task.isCompleted || task.isAbandoned ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Text(task.state == .archived || task.state == .abandonedArchived ? "已归档" : TaskStatus.remainingText(task, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("编辑任务")
    }
}
