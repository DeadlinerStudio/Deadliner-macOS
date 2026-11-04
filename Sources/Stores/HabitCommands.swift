import Foundation
import Shared

/// 编辑器里的习惯草稿。新建时 `id` 为 nil。
struct HabitDraft: Equatable {
    enum ScheduleKind: String, CaseIterable { case weeklyDays = "WEEKLY_DAYS", once = "ONCE", algorithm = "ALGORITHM" }
    enum GoalWindow: String, CaseIterable { case scheduledDay = "SCHEDULED_DAY", week = "WEEK", month = "MONTH", lifetime = "LIFETIME" }
    enum TrackingMode: String { case checkOff = "CHECK_OFF", quantity = "QUANTITY" }

    var id: String?
    var name = ""
    var note = ""
    var colorHex: String?
    var iconKey: String?
    var categoryId: String?
    var scheduleKind: ScheduleKind = .weeklyDays
    /// 周一为第 0 位（与 Core `HabitWeekdays` 一致）。
    var weekdaysMask = 0b111_1111
    var startOn = Calendar.current.startOfDay(for: Date())
    var endOn: Date?
    var goalWindow: GoalWindow = .scheduledDay
    var targetCount = 1
    var trackingMode: TrackingMode = .checkOff
    var unit = ""
    var defaultIncrement = 1
    var reminderEnabled = false
    var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

    /// 不满足时返回原因。这些条件与 Core 构造 HabitSchedule / HabitGoal / HabitTracking 时的检查一致——
    /// Core 的检查会直接抛出 Kotlin 异常而导致崩溃，所以必须在交给 Core 之前拦下。
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "名称不能为空" }
        if targetCount <= 0 { return "目标次数必须大于 0" }
        if defaultIncrement <= 0 { return "每次记录的数量必须大于 0" }
        if scheduleKind == .weeklyDays && !(1...0b111_1111).contains(weekdaysMask) { return "请至少选择一天" }
        if let endOn, Calendar.current.startOfDay(for: endOn) < Calendar.current.startOfDay(for: startOn) { return "结束日期不能早于开始日期" }
        return nil
    }
}

/// 习惯的写入命令：保存走 `HabitRepository.create` / `update`（与 Core HabitEditorViewModel.save 相同），
/// 归档 / 恢复走 `applyStatusAction`，删除走软删除。
@MainActor
final class HabitCommands {
    private let database: DeadlinerDatabase
    private let didChange: () -> Void

    init(database: DeadlinerDatabase, didChange: @escaping () -> Void) {
        self.database = database
        self.didChange = didChange
    }

    func draft(for uid: String) -> HabitDraft? {
        guard let habit = database.habits.find(uid: uid), !habit.isDeleted else { return nil }
        var draft = HabitDraft()
        draft.id = habit.uid
        draft.name = habit.name
        draft.note = habit.description_ ?? ""
        draft.colorHex = habit.color.map { HabitItem.hex(fromArgb: $0.intValue) }
        draft.iconKey = habit.iconKey
        draft.categoryId = habit.categoryUid
        draft.scheduleKind = HabitDraft.ScheduleKind(rawValue: habit.schedule.kind.name) ?? .weeklyDays
        draft.weekdaysMask = habit.schedule.weekdaysMask?.intValue ?? 0b111_1111
        draft.startOn = HabitDates.date(habit.schedule.startOn) ?? draft.startOn
        draft.endOn = habit.schedule.endOn.flatMap(HabitDates.date)
        draft.goalWindow = HabitDraft.GoalWindow(rawValue: habit.goal.window.name) ?? .scheduledDay
        draft.targetCount = Int(habit.goal.targetCount)
        draft.trackingMode = habit.tracking.mode.name == "QUANTITY" ? .quantity : .checkOff
        draft.unit = habit.tracking.unit ?? ""
        draft.defaultIncrement = Int(habit.tracking.defaultIncrement)
        if let reminder = habit.reminder {
            draft.reminderEnabled = reminder.isEnabled
            draft.reminderTime = Self.time(from: reminder.localTime) ?? draft.reminderTime
        }
        return draft
    }

    @discardableResult
    func save(_ draft: HabitDraft) throws -> String {
        if let message = draft.validationError { throw HabitCommandError.invalid(message) }
        let now = CoreClock.now()
        let existing = draft.id.flatMap { database.habits.find(uid: $0) }
        if draft.id != nil && (existing == nil || existing?.isDeleted == true) { throw HabitCommandError.notFound }

        let schedule = HabitSchedule(
            kind: HabitScheduleKind.entries.first { $0.name == draft.scheduleKind.rawValue }!,
            startOn: HabitDates.string(draft.startOn),
            endOn: draft.endOn.map(HabitDates.string),
            weekdaysMask: draft.scheduleKind == .weeklyDays ? KotlinInt(int: Int32(draft.weekdaysMask)) : nil,
            algorithmKey: draft.scheduleKind == .algorithm ? HabitAlgorithms.shared.EBBINGHAUS_CLASSIC_V1 : nil
        )
        let goal = HabitGoal(window: HabitGoalWindow.entries.first { $0.name == draft.goalWindow.rawValue }!, targetCount: Int32(draft.targetCount))
        let unit = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let tracking = HabitTracking(
            mode: draft.trackingMode == .quantity ? HabitTrackingMode.quantity : HabitTrackingMode.checkOff,
            unit: draft.trackingMode == .quantity && !unit.isEmpty ? unit : nil,
            defaultIncrement: Int32(draft.trackingMode == .quantity ? draft.defaultIncrement : 1)
        )
        let reminder = draft.reminderEnabled ? HabitReminder(localTime: Self.localTime(draft.reminderTime), isEnabled: true) : nil
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

        let habit = Habit_(
            uid: existing?.uid ?? PlatformIdentity.shared.doNewId(),
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: note.isEmpty ? nil : note,
            color: draft.colorHex.flatMap(Self.argb).map { KotlinInt(int: $0) },
            iconKey: draft.iconKey,
            categoryUid: draft.categoryId,
            schedule: schedule, goal: goal, tracking: tracking,
            status: existing?.status ?? HabitStatus.active,
            sortOrder: existing?.sortOrder ?? 0,
            reminder: reminder,
            createdAt: existing?.createdAt ?? now, updatedAt: now, isDeleted: false
        )
        if existing == nil {
            database.habits.create(habit: habit)
        } else {
            database.habits.update(habit: habit)
        }
        didChange()
        return habit.uid
    }

    /// 正在专注计时的习惯不能直接归档或删除（Core 会抛出异常），先交给界面确认结束计时。
    var isTiming: (String) -> Bool = { _ in false }
    var onTimerConflict: ((TimerConflict) -> Void)?

    func archive(_ uid: String) throws {
        if handledTimerConflict(uid, delete: false) { return }
        let outcome = database.habits.applyStatusAction(uid: uid, action: HabitStatusAction.archive, occurredAt: CoreClock.now()).outcome
        guard ["APPLIED", "NO_OP"].contains(outcome.name) else { throw HabitCommandError.notFound }
        didChange()
    }

    func delete(_ uid: String) {
        if handledTimerConflict(uid, delete: true) { return }
        database.habits.delete(uid: uid, updatedAt: CoreClock.now())
        didChange()
    }

    private func handledTimerConflict(_ uid: String, delete: Bool) -> Bool {
        guard isTiming(uid) else { return false }
        let title = draft(for: uid)?.name ?? ""
        onTimerConflict?(TimerConflict(targetId: uid, title: title, isHabit: true, action: nil, delete: delete))
        return true
    }

    // MARK: - Conversions

    /// `#RRGGBB` → 不透明的 ARGB 整数（Core 中习惯颜色的存储方式）。
    static func argb(_ hex: String) -> Int32? {
        let trimmed = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard trimmed.count == 6, let rgb = UInt32(trimmed, radix: 16) else { return nil }
        return Int32(bitPattern: 0xFF00_0000 | rgb)
    }

    /// 提醒时间 `HH:mm`（与 Core 的提醒时间格式一致）。
    static func localTime(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func time(from localTime: String) -> Date? {
        let parts = localTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
    }
}

enum HabitCommandError: LocalizedError, Equatable {
    case invalid(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .notFound: "习惯不存在，可能已在其他设备上删除"
        }
    }
}
