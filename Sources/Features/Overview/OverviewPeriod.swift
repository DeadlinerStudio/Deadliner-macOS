import Foundation

/// UI 日期边界与展示比较；任务聚合仍由 Core 负责。
enum OverviewPeriod {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }
    static func month(_ date: Date = Date()) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }
    static func shift(_ date: Date, months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: month(date))!
    }
    static func key(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func comparison(current: [Int], previous: [Int], day: Int) -> String {
        let count = current.prefix(day).reduce(0, +)
        let baseline = previous.prefix(day).reduce(0, +)
        let delta = count - baseline
        if delta == 0 { return "较上月同期持平" }
        if baseline == 0 { return "较上月同期新增 \(delta) 项" }
        return String(format: "较上月同期%@ %.1f%%", delta > 0 ? "增长" : "减少", abs(Double(delta) / Double(baseline)) * 100)
    }
}
