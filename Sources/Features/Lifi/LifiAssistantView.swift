import SwiftUI

/// Lifi AI 对话窗口（⌘L）：和 Deadliner 聊聊接下来要做什么，让它安排任务、建立习惯或回答关于任务的问题。
struct LifiAssistantView: View {
    @Bindable var store: LifiAssistantStore
    var openSettings: () -> Void
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.palette) private var t

    private let examples = [String(localized: "明天下午 3 点和产品开评审会"), String(localized: "每周 3 次力量训练，每次 40 分钟"), String(localized: "这周有什么快到期的任务？"), String(localized: "把这周要交付的任务排一下优先级")]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if store.messages.isEmpty { welcome }
                        ForEach(store.messages) { message in
                            row(message).id(message.id)
                        }
                        if let status = store.status, store.isRunning {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(status).font(.callout).foregroundStyle(.secondary)
                            }
                            .id("status")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: store.messages.count) {
                    withAnimation { proxy.scrollTo(store.messages.last?.id, anchor: .bottom) }
                }
            }
            Divider()
            composer
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 640)
        .background(t.pageBg)
        .toolbar {
            ToolbarItem {
                Button("新对话", systemImage: "square.and.pencil") { store.reset() }
                    .help("清空对话，开始新的会话（记忆保留）")
            }
        }
        .onAppear { inputFocused = true }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("我是 Lifi，你可以这样问我", systemImage: "sparkles").font(.headline)
            ForEach(examples, id: \.self) { example in
                Button(example) { store.send(example) }
                    .buttonStyle(.bordered)
                    .disabled(!store.canSend)
            }
            if !LifiSettings.isEnabled {
                HStack {
                    Text(LifiSettings.isAvailable ? "还没有启用 Lifi AI。" : "当前构建未包含 Lifi AI。")
                        .foregroundStyle(.secondary)
                    if LifiSettings.isAvailable { Button("打开设置", action: openSettings) }
                }
                .font(.callout)
            }
        }
        .padding(.bottom, 8)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("和 Deadliner 聊聊你接下来想做什么", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(10)
                .background(t.fieldBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if store.isRunning {
                Button("停止", systemImage: "stop.fill") { store.cancel() }
                    .labelStyle(.iconOnly)
                    .help("停止这次回答")
            } else {
                Button("发送", systemImage: "arrow.up.circle.fill", action: send)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.plain)
                    .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : t.primary)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("发送（⌘↩）")
            }
        }
        .padding(12)
    }

    private func send() {
        let text = input
        input = ""
        store.send(text)
    }

    @ViewBuilder
    private func row(_ message: LifiAssistantStore.Message) -> some View {
        switch message.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 60)
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(t.primary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .assistant(let text):
            Text(LocalizedStringKey(text))
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(t.cardBase, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .notice(let text):
            Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        case .error(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(t.error)
        case .approval(let id, let title, let detail, let resolved):
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary) }
                if let resolved {
                    Text(resolved).font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("允许一次") { store.resolve(id, .once) }.buttonStyle(.borderedProminent)
                        if title.hasPrefix(String(localized: "允许读取")) {
                            Button("记住本会话") { store.resolve(id, .session) }
                            Button("永久开启") { store.resolve(id, .always) }
                        }
                        Button("拒绝", role: .cancel) { store.resolve(id, .deny) }
                    }
                }
            }
            .padding(12)
            .background(t.cardBase, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .tasks(let proposals):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(proposals.count > 1 ? "批量任务：共 \(proposals.count) 条" : "任务").font(.headline)
                    Spacer()
                    if proposals.count > 1, proposals.contains(where: { $0.addedId == nil }) {
                        Button("全部添加") { store.addAllTasks(message: message.id) }
                    }
                }
                ForEach(proposals) { proposal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proposal.draft.title)
                            Text(proposal.draft.dueAt.map { String(localized: "截止：") + $0.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute()) } ?? String(localized: "未设置截止时间"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(proposal.addedId == nil ? "添加" : "撤回") { store.toggleTask(message: message.id, proposal: proposal.id) }
                    }
                }
            }
            .padding(12)
            .background(t.cardBase, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .habits(let proposals):
            VStack(alignment: .leading, spacing: 8) {
                Text(proposals.count > 1 ? "批量习惯：共 \(proposals.count) 条" : "习惯").font(.headline)
                ForEach(proposals) { proposal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proposal.draft.name)
                            Text(Self.habitSummary(proposal.draft)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(proposal.addedId == nil ? "建立" : "撤回") { store.toggleHabit(message: message.id, proposal: proposal.id) }
                    }
                }
            }
            .padding(12)
            .background(t.cardBase, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    static func habitSummary(_ draft: HabitDraft) -> String {
        let window = switch draft.goalWindow {
        case .scheduledDay: String(localized: "每个执行日")
        case .week: String(localized: "每周")
        case .month: String(localized: "每月")
        case .lifetime: String(localized: "累计")
        }
        var text = String(localized: "\(window) \(draft.targetCount) 次")
        if draft.reminderEnabled { text += String(localized: " · 提醒 ") + draft.reminderTime.formatted(.dateTime.hour().minute()) }
        return text
    }
}
