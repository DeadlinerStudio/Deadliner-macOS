import SwiftUI

/// 自定义的日期范围，起止都包含在内（按天）。存进 UserDefaults 时编码为 `yyyy-MM-dd|yyyy-MM-dd`。
struct DateRange: Equatable {
    var start: Date
    var end: Date

    init(start: Date, end: Date, calendar: Calendar = .current) {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        self.start = first
        self.end = last
    }

    /// 结束日的下一天，即 Core 使用的 `[start, endExclusive)`。
    func endExclusive(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }

    var dayCount: Int { (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        date >= start && date < endExclusive(calendar: calendar)
    }

    var encoded: String { "\(Self.iso.string(from: start))|\(Self.iso.string(from: end))" }

    static func decode(_ raw: String?) -> DateRange? {
        guard let parts = raw?.split(separator: "|"), parts.count == 2,
              let start = iso.date(from: String(parts[0])), let end = iso.date(from: String(parts[1])) else { return nil }
        return DateRange(start: start, end: end)
    }

    /// 「10月12日 – 12月31日」；不在今年时带年份。
    var label: String {
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: Date())
        func text(_ date: Date) -> String {
            let year = calendar.component(.year, from: date)
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = year == thisYear ? "M月d日" : "yyyy年M月d日"
            return f.string(from: date)
        }
        return start == end ? text(start) : "\(text(start)) – \(text(end))"
    }

    /// 与 Core 交换数据用的日期字符串（本地日期）。
    static func isoString(_ date: Date) -> String { iso.string(from: date) }

    /// 快捷选项：最近 7 天、最近 30 天、本季度、今年。
    static func presets(now: Date = Date(), calendar: Calendar = .current) -> [(title: String, range: DateRange)] {
        let today = calendar.startOfDay(for: now)
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today) ?? today }
        let month = calendar.component(.month, from: today)
        let year = calendar.component(.year, from: today)
        let quarterStart = calendar.date(from: DateComponents(year: year, month: (month - 1) / 3 * 3 + 1, day: 1)) ?? today
        let quarterEnd = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: quarterStart) ?? today
        let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? today
        let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? today
        return [
            ("最近 7 天", DateRange(start: daysAgo(6), end: today)),
            ("最近 30 天", DateRange(start: daysAgo(29), end: today)),
            ("本季度", DateRange(start: quarterStart, end: quarterEnd)),
            ("今年", DateRange(start: yearStart, end: yearEnd)),
        ]
    }

    /// 默认范围：最近 30 天。
    static var fallback: DateRange { presets()[1].range }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// 选择起止日期：左右两个日历，上方快捷选项。
struct DateRangeSheet: View {
    let initial: DateRange
    var onDone: (DateRange) -> Void
    var onCancel: () -> Void
    @State private var start: Date
    @State private var end: Date

    init(initial: DateRange, onDone: @escaping (DateRange) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onDone = onDone
        self.onCancel = onCancel
        _start = State(initialValue: initial.start)
        _end = State(initialValue: initial.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择时间范围").font(.headline)
            HStack(spacing: 8) {
                ForEach(DateRange.presets(), id: \.title) { preset in
                    Button(preset.title) {
                        start = preset.range.start
                        end = preset.range.end
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("开始").font(.caption).foregroundStyle(.secondary)
                    DatePicker("开始", selection: $start, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("结束").font(.caption).foregroundStyle(.secondary)
                    DatePicker("结束", selection: $end, in: start..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                }
            }
            HStack {
                let range = DateRange(start: start, end: end)
                Text(verbatim: "\(range.label) · 共 \(range.dayCount) 天")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("确定") { onDone(DateRange(start: start, end: end)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(DateRange(start: start, end: end).dayCount > 3660)
            }
        }
        .padding(20)
        .onChange(of: start) { if end < start { end = start } }
    }
}
