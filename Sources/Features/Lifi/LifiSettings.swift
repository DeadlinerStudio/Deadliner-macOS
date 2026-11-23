import Foundation
import Shared

/// Lifi AI 的设置。服务地址、模型和 API Key 与月度洞察共用一份（钥匙串中的同一条）。
/// 交互偏好与安卓相同：自动确认读取任务列表、静默添加任务、隐藏思考过程。
@MainActor
enum LifiSettings {
    static let enabledKey = "lifi.enabled"
    static let autoApproveReadKey = "lifi.autoApproveRead"
    static let silentAddKey = "lifi.silentAdd"
    static let hideThinkingKey = "lifi.hideThinking"
    /// 自定义提示词（与安卓相同）：从一段文字中识别任务时，附在用户原文之前，用来说明自己的习惯和要求。
    static let customPromptKey = "lifi.customPrompt"
    static let customPromptLimit = 2000

    static var customPrompt: String {
        (UserDefaults.standard.string(forKey: customPromptKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 交给 AI 识别的内容：有自定义提示词时放在原文之前。
    static func extractionInput(_ text: String, prompt: String = customPrompt) -> String {
        prompt.isEmpty ? text : prompt + "\n\n" + text
    }
    static let urlKey = "overview.ai.url"
    static let modelKey = "overview.ai.model"

    /// 这个构建是否包含 Lifi（公开构建为 stub，AI 不可用）。
    static var isAvailable: Bool { LifiAvailability.shared.isAvailable }

    static var isEnabled: Bool { isAvailable && UserDefaults.standard.bool(forKey: enabledKey) }

    static func apiKey(url: String) -> String? {
        MonthlyInsightSettings.keychain.password(url: url, username: "api")
    }

    /// 智能体用的配置。Lifi 的工具（读取 / 创建任务和习惯）只为 ios / android / harmony 声明，
    /// Mac 与 iOS 使用同一套 Apple 工具，所以平台名用 "ios"。
    static func configuration() -> AIConfig? {
        guard isEnabled else { return nil }
        let defaults = UserDefaults.standard
        let url = defaults.string(forKey: urlKey) ?? ""
        let model = (defaults.string(forKey: modelKey) ?? "").trimmingCharacters(in: .whitespaces)
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host != nil, !model.isEmpty,
              let key = apiKey(url: url), !key.isEmpty else { return nil }
        return AIConfig(apiKey: key, baseUrl: url, model: model, platform: "ios", timezone: TimeZone.current.identifier,
                        temperature: MonthlyInsightSettings.temperature(for: model).map { KotlinDouble(double: $0) },
                        nativeToolCalling: false, preferredLanguage: "zh-CN")
    }

    /// 配置的指纹：变化后重新创建 Lifi 会话。不含密钥原文。
    static func fingerprint() -> String {
        let defaults = UserDefaults.standard
        let url = defaults.string(forKey: urlKey) ?? ""
        let key = apiKey(url: url) ?? ""
        return [url, defaults.string(forKey: modelKey) ?? "", String(key.hashValue), TimeZone.current.identifier].joined(separator: "|")
    }
}

/// AI 返回的任务 / 习惯提案转成编辑器草稿（只在用户确认后保存）。
enum LifiDrafts {
    /// AI 的时间格式：`yyyy-MM-dd HH:mm`、`yyyy-MM-ddTHH:mm[:ss]`，或只有日期（当天 23:59）。
    static func parseDue(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let normalized = text.replacingOccurrences(of: " ", with: "T")
        if let date = TaskShareLink.parseLocal(String(normalized.prefix(19))) { return date }
        let parts = normalized.split(separator: "-").compactMap { Int($0) }
        if parts.count == 3, let day = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
            return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: day)
        }
        return nil
    }

    static func task(title: String, dueAt: String?, note: String?) -> TaskDraft {
        var draft = TaskDraft()
        draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.note = note ?? ""
        draft.dueAt = parseDue(dueAt)
        return draft
    }

    static func task(_ proposal: AiTaskProposal) -> TaskDraft {
        task(title: proposal.title, dueAt: proposal.dueAt, note: proposal.note)
    }

    static func habit(_ proposal: AiHabitProposal) -> HabitDraft {
        var draft = HabitDraft()
        draft.name = proposal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.scheduleKind = HabitDraft.ScheduleKind(rawValue: proposal.schedule.kind.name) ?? .weeklyDays
        if let mask = proposal.schedule.weekdaysMask?.intValue, (1...0b111_1111).contains(Int(mask)) { draft.weekdaysMask = Int(mask) }
        draft.goalWindow = HabitDraft.GoalWindow(rawValue: proposal.goal.window.name) ?? .scheduledDay
        draft.targetCount = max(1, Int(proposal.goal.targetCount))
        if let reminder = proposal.reminder, reminder.isEnabled, let time = reminderTime(reminder.localTime) {
            draft.reminderEnabled = true
            draft.reminderTime = time
        }
        return draft
    }

    /// 快速添加的提案（Core `QuickAddProposal` 的 JSON）。
    struct QuickProposal: Decodable, Equatable {
        var kind = "TASK"
        var title = ""
        var dueAt: String?
        var note = ""
        var period = "DAILY"
        var targetCount = 1
        var weekdaysMask = 127
        var reminderTime: String?
        var needsAI = false
        var ready = false
        var source = "LOCAL"
        var message = ""

        var isHabit: Bool { kind.uppercased() == "HABIT" }

        static func decode(_ json: String) -> QuickProposal? {
            try? JSONDecoder().decode(QuickProposal.self, from: Data(json.utf8))
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "TASK"
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            dueAt = try c.decodeIfPresent(String.self, forKey: .dueAt)
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            period = try c.decodeIfPresent(String.self, forKey: .period) ?? "DAILY"
            targetCount = try c.decodeIfPresent(Int.self, forKey: .targetCount) ?? 1
            weekdaysMask = try c.decodeIfPresent(Int.self, forKey: .weekdaysMask) ?? 127
            reminderTime = try c.decodeIfPresent(String.self, forKey: .reminderTime)
            needsAI = try c.decodeIfPresent(Bool.self, forKey: .needsAI) ?? false
            ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
            source = try c.decodeIfPresent(String.self, forKey: .source) ?? "LOCAL"
            message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        }

        private enum CodingKeys: String, CodingKey {
            case kind, title, dueAt, note, period, targetCount, weekdaysMask, reminderTime, needsAI, ready, source, message
        }

        var taskDraft: TaskDraft { LifiDrafts.task(title: title, dueAt: dueAt, note: note) }

        var habitDraft: HabitDraft {
            var draft = HabitDraft()
            draft.name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.note = note
            if (1...0b111_1111).contains(weekdaysMask) { draft.weekdaysMask = weekdaysMask }
            draft.targetCount = max(1, targetCount)
            draft.goalWindow = switch period.uppercased() {
            case "WEEKLY": .week
            case "MONTHLY": .month
            case "TOTAL": .lifetime
            default: .scheduledDay
            }
            if let time = reminderTime.flatMap(LifiDrafts.reminderTime) {
                draft.reminderEnabled = true
                draft.reminderTime = time
            }
            return draft
        }
    }

    static func reminderTime(_ text: String) -> Date? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
    }
}
