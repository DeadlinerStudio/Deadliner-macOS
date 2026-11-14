import Foundation
import Observation
import Shared

/// Lifi AI 对话（与 iOS / 安卓相同的智能体）：通过 Core 的 `IosLifiCore` 运行，工具调用在 Mac 上执行。
/// 读取任务 / 习惯需要用户允许（可以只允许一次、记住本次会话或永久开启）；
/// AI 提出的新任务 / 习惯先显示为草案，用户点「添加」才写入（开启「静默添加」时直接添加并可以撤回）。
@MainActor
@Observable
final class LifiAssistantStore {
    struct Message: Identifiable, Equatable {
        enum Kind: Equatable {
            case user(String)
            case assistant(String)
            case notice(String)
            case error(String)
            case approval(id: String, title: String, detail: String, resolved: String?)
            case tasks([Proposal])
            case habits([HabitProposal])
        }
        let id = UUID()
        var kind: Kind
    }

    struct Proposal: Identifiable, Equatable {
        let id = UUID()
        var draft: TaskDraft
        /// 已添加的任务 ID（可以撤回）。
        var addedId: String?
    }

    struct HabitProposal: Identifiable, Equatable {
        let id = UUID()
        var draft: HabitDraft
        var addedId: String?
    }

    private(set) var messages: [Message] = []
    private(set) var isRunning = false
    /// 正在进行的阶段（「正在思考」等）；开启「隐藏思考过程」时不显示。
    private(set) var status: String?

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private let taskCommands: TaskCommands
    @ObservationIgnored private let habitCommands: HabitCommands
    @ObservationIgnored private let didChange: () -> Void
    @ObservationIgnored private var core: IosLifiCore?
    @ObservationIgnored private var listener: Listener?
    @ObservationIgnored private var fingerprint: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingCalls: [String: ToolCall] = [:]
    /// 本次会话已允许读取（「记住本会话」）。
    @ObservationIgnored private var sessionAllowsRead = false
    @ObservationIgnored private var streamedReply = false

    init(database: DeadlinerDatabase, taskCommands: TaskCommands, habitCommands: HabitCommands, didChange: @escaping () -> Void) {
        self.database = database
        self.taskCommands = taskCommands
        self.habitCommands = habitCommands
        self.didChange = didChange
    }

    var canSend: Bool { !isRunning }

    // MARK: - 会话

    /// 配置变化时重新创建会话；没有配置时返回错误文字。
    private func ensureCore() -> String? {
        guard LifiSettings.isAvailable else { return "当前构建未包含 Lifi AI" }
        guard let config = LifiSettings.configuration() else { return "请先在「设置 → Lifi AI」中启用并填写服务地址、模型和 API Key" }
        let print = LifiSettings.fingerprint()
        if core != nil && fingerprint == print { return nil }
        close()
        generation &+= 1
        let current = generation
        let newCore = IosLifiCore.companion.createWithDatabase(config: config, database: database, ownsDatabase: false)
        let newListener = Listener { [weak self] event in
            _Concurrency.Task { @MainActor in self?.handle(event, generation: current) }
        }
        newCore.start(listener: newListener)
        core = newCore
        listener = newListener
        fingerprint = print
        return nil
    }

    /// 快速添加用的 AI 识别（与 iOS 相同，走 Core 的 `IosQuickAddBridge`）。返回 `QuickAddProposal` 的 JSON。
    func extractQuickAdd(_ text: String, kind: String) async throws -> String {
        if let problem = ensureCore() { throw LifiError(message: problem) }
        guard let core else { throw LifiError(message: "Lifi 尚未初始化") }
        return try await IosQuickAddBridge().extractJson(core: core, text: text, kind: kind)
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        messages.append(Message(kind: .user(text)))
        if let problem = ensureCore() {
            messages.append(Message(kind: .error(problem)))
            return
        }
        guard let core else { return }
        isRunning = true
        streamedReply = false
        status = "Lifi 正在思考…"
        _Concurrency.Task {
            do {
                try await core.processInput(text: text)
            } catch {
                finish(error: "请求失败：\(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        guard let core, isRunning else { return }
        _Concurrency.Task { try? await core.cancelRun() }
        finish(error: nil)
        messages.append(Message(kind: .notice("已停止")))
    }

    /// 清空对话并开始新的会话（记忆保留）。
    func reset() {
        close()
        messages = []
        sessionAllowsRead = false
        status = nil
        isRunning = false
    }

    func close() {
        core?.close()
        core = nil
        listener = nil
        fingerprint = nil
        pendingCalls = [:]
    }

    private func finish(error: String?) {
        isRunning = false
        status = nil
        if let error { messages.append(Message(kind: .error(error))) }
    }

    // MARK: - 事件

    private func handle(_ event: CoreEvent, generation eventGeneration: Int) {
        guard eventGeneration == generation else { return }
        switch event {
        case let event as CoreEvent.OnThinking:
            if !UserDefaults.standard.bool(forKey: LifiSettings.hideThinkingKey) {
                status = event.message ?? Self.phaseText(agent: event.agentName, phase: event.phase)
            }
        case let event as CoreEvent.OnTextStream:
            streamedReply = true
            if case .assistant(let text) = messages.last?.kind {
                messages[messages.count - 1].kind = .assistant(text + event.chunk)
            } else {
                messages.append(Message(kind: .assistant(event.chunk)))
            }
        case let event as CoreEvent.OnToolRequest:
            handleTool(id: event.id, call: event.tool)
        case let event as CoreEvent.OnFinish:
            let result = event.result
            if !streamedReply, let reply = result.chatResponse?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
                messages.append(Message(kind: .assistant(reply)))
            }
            present(tasks: result.tasks.map(LifiDrafts.task), habits: result.habits.map(LifiDrafts.habit))
            finish(error: nil)
        case let event as CoreEvent.OnMemoryCommitted:
            for memory in event.addedMemories where !memory.trimmingCharacters(in: .whitespaces).isEmpty {
                messages.append(Message(kind: .notice("记住了：\(memory)")))
            }
        case let event as CoreEvent.OnError:
            finish(error: event.message)
        default:
            break
        }
    }

    static func phaseText(agent: String, phase: String) -> String {
        switch phase.lowercased() {
        case "deciding", "thinking": "\(agent) 正在思考…"
        case "tool", "waiting_tool", "awaiting_tool": "\(agent) 正在等待工具结果…"
        case "responding", "streaming": "\(agent) 正在组织回复…"
        default: "\(agent) 正在处理（\(phase)）…"
        }
    }

    // MARK: - 工具

    private func handleTool(id: String, call: ToolCall) {
        let autoRead = sessionAllowsRead || UserDefaults.standard.bool(forKey: LifiSettings.autoApproveReadKey)
        if (LifiToolExecutor.isRead(call) && !autoRead) || LifiToolExecutor.isWrite(call) {
            pendingCalls[id] = call
            messages.append(Message(kind: .approval(id: id, title: Self.approvalTitle(call), detail: Self.approvalDetail(call), resolved: nil)))
            status = "等待你的确认"
            return
        }
        run(id: id, call: call)
    }

    enum Approval { case once, session, always, deny }

    func resolve(_ id: String, _ answer: Approval) {
        guard let call = pendingCalls.removeValue(forKey: id) else { return }
        let resolved: String
        switch answer {
        case .once: resolved = "已允许一次"
        case .session: sessionAllowsRead = true; resolved = "已允许（本次会话）"
        case .always: UserDefaults.standard.set(true, forKey: LifiSettings.autoApproveReadKey); resolved = "已永久允许读取"
        case .deny: resolved = "已拒绝"
        }
        if let index = messages.firstIndex(where: { if case .approval(let key, _, _, nil) = $0.kind { return key == id }; return false }),
           case .approval(_, let title, let detail, _) = messages[index].kind {
            messages[index].kind = .approval(id: id, title: title, detail: detail, resolved: resolved)
        }
        status = "Lifi 正在思考…"
        if answer == .deny {
            submit(id: id, result: LifiToolExecutor.denied(call))
        } else {
            run(id: id, call: call)
        }
    }

    private func run(id: String, call: ToolCall) {
        let result = LifiToolExecutor(database: database, didChange: didChange).execute(call)
        if !LifiToolExecutor.isRead(call) || !UserDefaults.standard.bool(forKey: LifiSettings.hideThinkingKey) {
            messages.append(Message(kind: .notice(result.message)))
        }
        submit(id: id, result: result)
    }

    private func submit(id: String, result: LifiToolExecutor.Result) {
        guard let core else { return }
        _Concurrency.Task {
            do {
                try await core.submitToolResult(toolCallId: id, tool: result.tool, payload: result.json)
            } catch {
                finish(error: "工具结果回传失败：\(error.localizedDescription)")
            }
        }
    }

    static func approvalTitle(_ call: ToolCall) -> String {
        switch call {
        case is ToolCall.ReadTasks: "允许读取任务列表？"
        case is ToolCall.ReadHabits: "允许读取习惯列表？"
        case is ToolCall.UpdateDeadline: "允许修改截止时间？"
        default: "允许执行这次操作？"
        }
    }

    static func approvalDetail(_ call: ToolCall) -> String {
        var lines: [String] = []
        if let reason = call.reason, !reason.isEmpty { lines.append(reason) }
        if let update = call as? ToolCall.UpdateDeadline {
            lines.append("新的截止时间：\(update.newDueTime)")
        } else if LifiToolExecutor.isRead(call) {
            lines.append("为了回答你的问题，Lifi 需要查看相关内容。你可以只允许本次，也可以记住本会话，或直接永久开启自动确认。")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 提案

    private func present(tasks: [TaskDraft], habits: [HabitDraft]) {
        let silent = UserDefaults.standard.bool(forKey: LifiSettings.silentAddKey)
        if !tasks.isEmpty {
            var proposals = tasks.filter(\.isValid).map { Proposal(draft: $0) }
            if silent { for index in proposals.indices { proposals[index].addedId = try? taskCommands.save(proposals[index].draft) } }
            messages.append(Message(kind: .tasks(proposals)))
            if silent { messages.append(Message(kind: .notice("已静默添加 \(proposals.filter { $0.addedId != nil }.count) 条任务，若有误可以撤回"))) }
        }
        if !habits.isEmpty {
            var proposals = habits.filter { $0.validationError == nil }.map { HabitProposal(draft: $0) }
            if silent { for index in proposals.indices { proposals[index].addedId = try? habitCommands.save(proposals[index].draft) } }
            messages.append(Message(kind: .habits(proposals)))
        }
    }

    /// 添加或撤回一条任务提案。
    func toggleTask(message: UUID, proposal: UUID) {
        updateTasks(message) { item in
            if let id = item.addedId {
                try? taskCommands.delete(id)
                item.addedId = nil
            } else {
                item.addedId = try? taskCommands.save(item.draft)
            }
        } where: { $0.id == proposal }
    }

    func addAllTasks(message: UUID) {
        updateTasks(message) { item in item.addedId = try? taskCommands.save(item.draft) } where: { $0.addedId == nil }
    }

    func toggleHabit(message: UUID, proposal: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == message }), case .habits(var items) = messages[index].kind,
              let row = items.firstIndex(where: { $0.id == proposal }) else { return }
        if let id = items[row].addedId {
            habitCommands.delete(id)
            items[row].addedId = nil
        } else {
            items[row].addedId = try? habitCommands.save(items[row].draft)
        }
        messages[index].kind = .habits(items)
    }

    private func updateTasks(_ message: UUID, _ body: (inout Proposal) -> Void, where match: (Proposal) -> Bool) {
        guard let index = messages.firstIndex(where: { $0.id == message }), case .tasks(var items) = messages[index].kind else { return }
        for row in items.indices where match(items[row]) { body(&items[row]) }
        messages[index].kind = .tasks(items)
    }

    struct LifiError: LocalizedError { let message: String; var errorDescription: String? { message } }

    private final class Listener: IosLifiEventListener {
        let handler: (CoreEvent) -> Void
        init(handler: @escaping (CoreEvent) -> Void) { self.handler = handler }
        func onEvent(event: CoreEvent) { handler(event) }
    }
}
