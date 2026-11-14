import SwiftUI
import Shared

/// 快速添加（与 iOS / 安卓相同）：输入一句话，实时预览成任务或习惯；
/// 本机先按规则识别（Core `QuickAddParser`），复杂表达可以点「AI 识别」；随时可以展开完整表单。
/// 不使用本地识别模型（Kivo）。
struct QuickAddSheet: View {
    let lifi: LifiAssistantStore
    let taskCommands: TaskCommands
    let habitCommands: HabitCommands
    var openTaskEditor: (TaskDraft) -> Void
    var openHabitEditor: (HabitDraft) -> Void
    var onAdded: (String) -> Void
    var onClose: () -> Void

    @State private var text = ""
    @State private var kind = "TASK"
    @State private var proposal: LifiDrafts.QuickProposal?
    @State private var recognizing = false
    @State private var message: String?
    @FocusState private var focused: Bool
    @Environment(\.palette) private var t

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("一句话，安排得明明白白", text: $text, prompt: Text("例如：明天下午3点交报告 / 每天读书"))
                        .labelsHidden()
                        .focused($focused)
                        .onSubmit(add)
                    Picker("类型", selection: $kind) {
                        Text("任务").tag("TASK")
                        Text("习惯").tag("HABIT")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    if let proposal, !proposal.title.isEmpty {
                        preview(proposal)
                    } else {
                        Text("输入后在这里实时预览").foregroundStyle(.secondary)
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    Text(proposal?.source == "AI" ? "AI 识别结果" : "规则识别")
                } footer: {
                    if LifiSettings.isEnabled {
                        Text("复杂表达可以点「AI 识别」。识别结果只是预览，点「添加」后才保存。")
                    } else {
                        Text("复杂表达需要 AI（在「设置 → Lifi AI」中启用），也可以展开完整表单添加。")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("快速添加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                ToolbarItem(placement: .primaryAction) {
                    Button("展开完整表单", systemImage: "rectangle.expand.vertical") { expand() }
                }
                if LifiSettings.isEnabled {
                    ToolbarItem(placement: .primaryAction) {
                        Button(recognizing ? "识别中…" : "AI 识别", systemImage: "sparkles") { recognize() }
                            .disabled(recognizing || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加", action: add).disabled(!canAdd)
                }
            }
        }
        .frame(width: 460, height: 380)
        .onAppear { focused = true }
        .onChange(of: text) { parse() }
        .onChange(of: kind) { parse() }
    }

    private var canAdd: Bool {
        guard let proposal, !proposal.title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return proposal.isHabit ? proposal.habitDraft.validationError == nil : true
    }

    @ViewBuilder
    private func preview(_ proposal: LifiDrafts.QuickProposal) -> some View {
        LabeledContent(proposal.isHabit ? "习惯" : "任务", value: proposal.title)
        if proposal.isHabit {
            LabeledContent("目标", value: LifiAssistantView.habitSummary(proposal.habitDraft))
        } else {
            LabeledContent("截止", value: proposal.taskDraft.dueAt.map { $0.formatted(.dateTime.year().month().day().weekday(.abbreviated).hour().minute()) } ?? "未指定")
        }
        if !proposal.note.isEmpty { LabeledContent("备注", value: proposal.note) }
    }

    private func parse() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { proposal = nil; message = nil; return }
        let json = QuickAddParser().parseJson(text: input, preferredKind: kind, timezone: TimeZone.current.identifier)
        proposal = LifiDrafts.QuickProposal.decode(json)
        message = proposal.flatMap { $0.message.isEmpty ? ($0.needsAI ? "这句话比较复杂，可以用 AI 识别或展开补充" : nil) : $0.message }
    }

    private func recognize() {
        let input = text
        recognizing = true
        message = nil
        _Concurrency.Task {
            do {
                let json = try await lifi.extractQuickAdd(input, kind: kind)
                if let result = LifiDrafts.QuickProposal.decode(json), !result.title.isEmpty {
                    proposal = result
                    message = result.message.isEmpty ? nil : result.message
                } else {
                    message = "AI 没有识别出内容，请修改后重试或展开补充"
                }
            } catch {
                message = "AI 识别失败：\(error.localizedDescription)"
            }
            recognizing = false
        }
    }

    private func expand() {
        let current = proposal ?? LifiDrafts.QuickProposal.decode(#"{"kind":"\#(kind)","title":""}"#)
        if (current?.isHabit ?? false) || (current == nil && kind == "HABIT") {
            var draft = current?.habitDraft ?? HabitDraft()
            if draft.name.isEmpty { draft.name = text }
            openHabitEditor(draft)
        } else {
            var draft = current?.taskDraft ?? TaskDraft()
            if draft.title.isEmpty { draft.title = text }
            openTaskEditor(draft)
        }
    }

    private func add() {
        guard canAdd, let proposal else { return }
        do {
            if proposal.isHabit {
                try habitCommands.save(proposal.habitDraft)
                onAdded("已开启习惯：\(proposal.title)")
            } else {
                try taskCommands.save(proposal.taskDraft)
                onAdded("已添加任务：\(proposal.title)")
            }
        } catch {
            message = "保存失败：\(error.localizedDescription)"
        }
    }
}

/// 记忆管理（与 iOS / 安卓相同）：用户画像与碎片记忆，供 Lifi 了解你的偏好。随同步在设备之间保持一致。
struct LifiMemorySheet: View {
    let database: DeadlinerDatabase
    var onClose: () -> Void

    @State private var profile = ""
    @State private var fragments: [MemoryFragment] = []
    @State private var editing: MemoryFragment?
    @State private var editingText = ""
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $profile)
                        .font(.body)
                        .frame(minHeight: 90)
                    HStack {
                        Spacer()
                        Button("保存画像") {
                            database.memory.updateUserProfile(profile: profile.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .disabled(profile == database.memory.getUserProfile())
                    }
                } header: {
                    Text("用户画像")
                } footer: {
                    Text("画像用于给 Lifi 提供稳定的偏好与背景，建议控制在几百字以内。")
                }
                Section {
                    if fragments.isEmpty { Text("暂无碎片记忆").foregroundStyle(.secondary) }
                    ForEach(fragments, id: \.uid) { fragment in
                        HStack(alignment: .firstTextBaseline) {
                            Text(fragment.content).textSelection(.enabled)
                            Spacer()
                            Button("编辑") { editing = fragment; editingText = fragment.content }
                            Button("删除", role: .destructive) {
                                database.memory.delete(uid: fragment.uid, updatedAt: CoreClock.now())
                                reload()
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("碎片记忆（\(fragments.count)）")
                } footer: {
                    Text("建议把碎片记忆写成可复用的事实、偏好或约束，避免情绪化的长文本。")
                }
                Section {
                    Button("清空所有记忆", role: .destructive) { confirmClear = true }
                        .disabled(fragments.isEmpty && profile.isEmpty)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("记忆管理")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) } }
        }
        .frame(width: 500, height: 560)
        .onAppear(perform: reload)
        .sheet(item: Binding(get: { editing.map { EditingFragment(fragment: $0) } }, set: { if $0 == nil { editing = nil } })) { item in
            NavigationStack {
                Form { TextEditor(text: $editingText).frame(minHeight: 120) }
                    .formStyle(.grouped)
                    .navigationTitle("编辑碎片记忆")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                let content = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !content.isEmpty {
                                    let f = item.fragment
                                    database.memory.update(fragment: MemoryFragment(uid: f.uid, content: content, category: f.category,
                                                                                    createdAt: f.createdAt, importance: f.importance,
                                                                                    updatedAt: CoreClock.now(), isDeleted: false))
                                }
                                editing = nil
                                reload()
                            }
                        }
                    }
            }
            .frame(width: 420, height: 260)
        }
        .confirmationDialog("确认清空所有记忆？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) {
                let now = CoreClock.now()
                for fragment in fragments { database.memory.delete(uid: fragment.uid, updatedAt: now) }
                database.memory.updateUserProfile(profile: "")
                reload()
            }
        } message: {
            Text("这会清空用户画像和所有碎片记忆，且不可恢复。启用同步后也会同步到其他设备。")
        }
    }

    private struct EditingFragment: Identifiable {
        let fragment: MemoryFragment
        var id: String { fragment.uid }
    }

    private func reload() {
        profile = database.memory.getUserProfile()
        fragments = database.memory.list().filter { !$0.isDeleted }
    }
}
