import SwiftUI

/// 归档页：已归档的任务（沿用任务卡片，降低不透明度）与已归档的习惯。
struct ArchiveView: View {
    let store: ArchiveStore
    let commands: TaskCommands

    @State private var selectedTask: TaskItem?
    @State private var pendingDeleteTask: TaskItem?
    @State private var pendingDeleteHabit: ArchiveStore.ArchivedHabit?
    @State private var errorMessage: String?
    @AppStorage(CardLayout.storageKey) private var layoutRaw = CardLayout.single.rawValue
    @Environment(\.palette) private var t

    var body: some View {
        ArchiveContent(
            tasks: store.tasks,
            habits: store.habits,
            categories: store.categories,
            onTapTask: { selectedTask = $0 },
            onRestoreHabit: { habit in run { try store.restoreHabit(habit.id) } },
            onDeleteHabit: { pendingDeleteHabit = $0 },
            layout: CardLayout(rawValue: layoutRaw) ?? .single
        )
        .topAtmosphere(t.secondary)
        .navigationTitle("归档")
        .navigationSubtitle("\(store.tasks.count) 个任务 · \(store.habits.count) 个习惯")
        .onAppear { store.refresh() }
        .confirmationDialog(selectedTask?.title ?? "", isPresented: Binding(
            get: { selectedTask != nil }, set: { if !$0 { selectedTask = nil } }
        ), presenting: selectedTask) { task in
            Button("取消归档") { run { try commands.unarchive(task.id) } }
            Button("删除", role: .destructive) { pendingDeleteTask = task }
        }
        .confirmationDialog("确定要删除「\(pendingDeleteTask?.title ?? "")」吗？", isPresented: Binding(
            get: { pendingDeleteTask != nil }, set: { if !$0 { pendingDeleteTask = nil } }
        ), presenting: pendingDeleteTask) { task in
            Button("删除", role: .destructive) { run { try commands.delete(task.id) } }
        } message: { _ in
            Text("启用同步后，删除也会同步到手机。")
        }
        .confirmationDialog("确定要删除习惯「\(pendingDeleteHabit?.name ?? "")」吗？", isPresented: Binding(
            get: { pendingDeleteHabit != nil }, set: { if !$0 { pendingDeleteHabit = nil } }
        ), presenting: pendingDeleteHabit) { habit in
            Button("删除", role: .destructive) { store.deleteHabit(habit.id) }
        } message: { _ in
            Text("打卡记录会一并删除。启用同步后，删除也会同步到手机。")
        }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = error.localizedDescription }
    }
}

/// 不依赖 Core 的页面主体，便于截图测试。
struct ArchiveContent: View {
    let tasks: [TaskItem]
    let habits: [ArchiveStore.ArchivedHabit]
    let categories: [String: CategoryItem]
    var onTapTask: ((TaskItem) -> Void)?
    var onRestoreHabit: ((ArchiveStore.ArchivedHabit) -> Void)?
    var onDeleteHabit: ((ArchiveStore.ArchivedHabit) -> Void)?
    var layout: CardLayout = .single
    @Environment(\.palette) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tasks.isEmpty && habits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "archivebox").font(.system(size: 36))
                    Text("还没有归档的内容。已完成或已放弃的任务可以在右键菜单中归档。").font(.callout)
                }
                .foregroundStyle(t.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 18) {
                        if !tasks.isEmpty {
                            sectionTitle("任务")
                            LazyVGrid(columns: layout.columns, spacing: MiuixCard.gap) {
                                ForEach(tasks) { task in
                                    TaskCard(task: task, category: task.categoryId.flatMap { categories[$0] }, now: Date())
                                        .opacity(0.72)
                                        .contentShape(RoundedRectangle(cornerRadius: MiuixRadius.card))
                                        .onTapGesture { onTapTask?(task) }
                                        .help("点击取消归档或删除")
                                }
                            }
                        }
                        if !habits.isEmpty {
                            sectionTitle("习惯")
                            MiuixGroup {
                                ForEach(habits) { habit in
                                    MiuixRow(title: habit.name, systemImage: "target",
                                             tint: habit.colorHex.flatMap { Color(hexString: $0) } ?? t.primary) {
                                        Button("恢复") { onRestoreHabit?(habit) }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(t.primary)
                                        Button("删除") { onDeleteHabit?(habit) }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(t.error)
                                    }
                                }
                            }

                        }
                    }
                    .readableWidth(layout.maxContentWidth)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(t.onSurfaceVariant)
            .padding(.leading, 4)
    }
}
