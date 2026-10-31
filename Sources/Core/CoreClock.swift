import Foundation

/// 写入 Core 时使用的时间字符串，格式与 CoreDates 的解析规则对应。
enum CoreClock {
    /// `createdAt` / `updatedAt` 等：UTC ISO-8601，带毫秒，以 `Z` 结尾。
    static func now() -> String { instant(Date()) }

    static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// 任务的 `startAt` / `dueAt`：本地时间、不带时区，`yyyy-MM-ddTHH:mm:ss`。
    static func local(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
}
