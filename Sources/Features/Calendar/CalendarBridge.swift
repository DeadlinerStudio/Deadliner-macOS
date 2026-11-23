import EventKit
import Foundation

/// 与系统日历互通（与安卓「保存到日历」「从日历导入」相同）：只在用户点按时访问日历，不做自动同步，
/// 不改 Core（任务里不记录日历事件 ID，重复保存时按标题和时间判断）。
@MainActor
final class CalendarBridge {
    static let shared = CalendarBridge()
    /// 导入时不显示的日历（与安卓「自定义日历导入黑名单」相同），逗号分隔的日历 ID。
    static let excludedKey = "calendar.excludedCalendars"

    let store = EKEventStore()

    enum BridgeError: LocalizedError, Equatable {
        case denied, noDeadline, noCalendar

        var errorDescription: String? {
            switch self {
            case .denied: String(localized: "没有日历权限。请在「系统设置 → 隐私与安全性 → 日历」中允许 Deadliner for macOS。")
            case .noDeadline: String(localized: "这个任务没有截止时间，无法放进日历")
            case .noCalendar: String(localized: "没有可写入的日历，请先在「日历」App 中添加一个日历")
            }
        }
    }

    enum SaveResult: Equatable { case saved(calendar: String), duplicate(calendar: String) }

    func requestAccess() async throws {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw BridgeError.denied }
    }

    /// 事件的时间：开始取任务的开始时间（没有或晚于截止时为截止前 1 小时），结束取截止时间。
    nonisolated static func eventTimes(start: Date?, due: Date?) -> (start: Date, end: Date)? {
        guard let due else { return nil }
        let fallback = due.addingTimeInterval(-3600)
        guard let start, start < due else { return (fallback, due) }
        return (start, due)
    }

    nonisolated static func eventNotes(_ draft: TaskDraft) -> String {
        var lines: [String] = []
        if !draft.note.isEmpty { lines.append(draft.note) }
        if !draft.subtasks.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines += draft.subtasks.map { "\($0.isCompleted ? "☑︎" : "☐") \($0.content)" }
        }
        return lines.joined(separator: "\n")
    }

    /// 保存到默认日历；同一日历中已有同名、同时间的事件时不再重复添加。
    func save(_ draft: TaskDraft) async throws -> SaveResult {
        guard let times = Self.eventTimes(start: draft.startAt, due: draft.dueAt) else { throw BridgeError.noDeadline }
        try await requestAccess()
        guard let calendar = store.defaultCalendarForNewEvents else { throw BridgeError.noCalendar }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = store.events(matching: store.predicateForEvents(withStart: times.start, end: times.end, calendars: [calendar]))
        if existing.contains(where: { $0.title == title && $0.startDate == times.start && $0.endDate == times.end }) {
            return .duplicate(calendar: calendar.title)
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = times.start
        event.endDate = times.end
        event.notes = Self.eventNotes(draft)
        try store.save(event, span: .thisEvent, commit: true)
        return .saved(calendar: calendar.title)
    }

    // MARK: - 导入

    struct Calendar_: Identifiable, Hashable {
        let id: String
        let title: String
        let source: String
    }

    struct Event: Identifiable, Hashable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let notes: String
        let calendarId: String
        let calendarTitle: String
    }

    func calendars() -> [Calendar_] {
        store.calendars(for: .event)
            .map { Calendar_(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "") }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// 接下来 `days` 天内的事件（排除黑名单中的日历）。
    func upcomingEvents(days: Int, excluding: Set<String>, now: Date = Date()) -> [Event] {
        let calendars = store.calendars(for: .event).filter { !excluding.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let start = Foundation.Calendar.current.startOfDay(for: now)
        let end = Foundation.Calendar.current.date(byAdding: .day, value: days, to: start)!
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
            .map { Event(id: $0.calendarItemIdentifier + "|" + ($0.startDate?.timeIntervalSince1970.description ?? ""),
                         title: $0.title ?? "", start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay,
                         notes: $0.notes ?? "", calendarId: $0.calendar.calendarIdentifier, calendarTitle: $0.calendar.title) }
            .sorted { $0.start < $1.start }
    }

    /// 事件 → 新任务草稿：截止取事件结束时间；全天事件截止在最后一天的 23:59。
    nonisolated static func draft(from event: Event, calendar: Foundation.Calendar = .current) -> TaskDraft {
        var draft = TaskDraft()
        draft.title = event.title.isEmpty ? String(localized: "日历事件") : event.title
        draft.note = event.notes
        if event.isAllDay {
            let lastDay = calendar.date(byAdding: .second, value: -1, to: event.end) ?? event.end
            draft.startAt = calendar.startOfDay(for: event.start)
            draft.dueAt = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: lastDay)
        } else {
            draft.startAt = event.start
            draft.dueAt = event.end
        }
        return draft
    }

    static func excluded(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.string(forKey: excludedKey) ?? "").split(separator: ",").map(String.init))
    }

    static func setExcluded(_ ids: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(ids.sorted().joined(separator: ","), forKey: excludedKey)
    }
}
