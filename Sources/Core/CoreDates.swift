import Foundation

/// Core 与手机共用的时间格式（见规范 v6 第 5.3 节）：
/// - 任务的 `startAt` / `dueAt`：本地时间、不带时区，`yyyy-MM-ddTHH:mm:ss`（兼容不带秒）。
/// - `createdAt` / `updatedAt` / `completedAt`：UTC ISO-8601，以 `Z` 结尾，可能带毫秒。
enum CoreDates {
    static func parseLocal(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return localWithSeconds.date(from: value) ?? localWithoutSeconds.date(from: value)
    }

    static func parseInstant(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return instantFractional.date(from: value) ?? instant.date(from: value)
    }

    private static func localFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    private static let localWithSeconds = localFormatter("yyyy-MM-dd'T'HH:mm:ss")
    private static let localWithoutSeconds = localFormatter("yyyy-MM-dd'T'HH:mm")
    nonisolated(unsafe) private static let instant: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    nonisolated(unsafe) private static let instantFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
