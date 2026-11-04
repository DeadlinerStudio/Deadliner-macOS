import SwiftUI

/// 日期选择的取值范围；nil 表示该侧不限。
struct DatePickerBounds: Equatable {
    var lower: Date?
    var upper: Date?

    static let unbounded = DatePickerBounds()
    static func from(_ date: Date) -> DatePickerBounds { DatePickerBounds(lower: date) }
    static func through(_ date: Date) -> DatePickerBounds { DatePickerBounds(upper: date) }
    static func between(_ lower: Date, _ upper: Date) -> DatePickerBounds { DatePickerBounds(lower: lower, upper: upper) }
}

/// 选择器的组成部分：只选日期、只选时间、日期加时间。
enum DeadlinerDatePickerMode {
    case date, time, dateAndTime

    var hasDate: Bool { self != .time }
    var hasTime: Bool { self != .date }
}

/// 选择器里的日期计算，与视图分开以便测试。日历一律从周一开始。
enum DeadlinerDateMath {
    enum QuickDay: CaseIterable {
        case today, tomorrow, weekend, nextMonday

        var title: String {
            switch self {
            case .today: "今天"
            case .tomorrow: "明天"
            case .weekend: "本周末"
            case .nextMonday: "下周一"
            }
        }
    }

    /// 常用时间（时, 分）。
    static let commonTimes: [(hour: Int, minute: Int)] = [(9, 0), (12, 0), (18, 0), (23, 59)]

    static func mondayFirst(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    /// 快捷日期（当天零点）。「本周末」是本周六，周日当天算今天；「下周一」总是下一周的周一。
    static func day(_ quick: QuickDay, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 = 周日 … 7 = 周六
        let offset: Int = switch quick {
        case .today: 0
        case .tomorrow: 1
        case .weekend: weekday == 1 ? 0 : 7 - weekday
        case .nextMonday: (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7
        }
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// 取 `day` 的年月日和 `time` 的时分。
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return setTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0, on: day, calendar: calendar)
    }

    static func setTime(hour: Int, minute: Int, on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    static func shiftMonth(_ month: Date, by offset: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: offset, to: monthStart(month, calendar: calendar)) ?? month
    }

    /// 某月的格子：固定 6 行 × 7 列（周一到周日），不属于本月的位置为 nil。
    static func monthGrid(for month: Date, calendar: Calendar = .current) -> [[Date?]] {
        let first = monthStart(month, calendar: calendar)
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let leading = (calendar.component(.weekday, from: first) + 5) % 7 // 周一 = 0
        var cells: [Date?] = Array(repeating: nil, count: leading)
        cells += (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
        cells += Array(repeating: nil, count: 42 - cells.count)
        return stride(from: 0, to: 42, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// 按模式把值限制在范围内；只选日期时按整天比较，保留原来的时分。
    static func clamp(_ date: Date, to bounds: DatePickerBounds, mode: DeadlinerDatePickerMode = .dateAndTime,
                      calendar: Calendar = .current) -> Date {
        if mode == .date {
            let day = calendar.startOfDay(for: date)
            if let lower = bounds.lower, day < calendar.startOfDay(for: lower) {
                return combine(day: lower, time: date, calendar: calendar)
            }
            if let upper = bounds.upper, day > calendar.startOfDay(for: upper) {
                return combine(day: upper, time: date, calendar: calendar)
            }
            return date
        }
        if let lower = bounds.lower, date < lower { return lower }
        if let upper = bounds.upper, date > upper { return upper }
        return date
    }

    /// 这一天是否有任何时刻落在范围内。
    static func isSelectable(_ day: Date, bounds: DatePickerBounds, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        if let lower = bounds.lower, start < calendar.startOfDay(for: lower) { return false }
        if let upper = bounds.upper, start > calendar.startOfDay(for: upper) { return false }
        return true
    }

    /// 解析手输时间：「9」「9:30」「0930」「930」「9.30」「9：30」。
    static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(whereSeparator: { ":：.".contains($0) }).map(String.init)
        let hour: Int?, minute: Int?
        if parts.count == 2 {
            hour = Int(parts[0]); minute = Int(parts[1])
        } else if parts.count == 1, trimmed.allSatisfy(\.isNumber) {
            switch trimmed.count {
            case 1, 2: hour = Int(trimmed); minute = 0
            case 3, 4: hour = Int(trimmed.dropLast(2)); minute = Int(trimmed.suffix(2))
            default: return nil
            }
        } else { return nil }
        guard let hour, let minute, (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// 字段上显示的文字：今天 / 明天 / 11月5日 周四，跨年时带年份。
    static func label(_ date: Date, mode: DeadlinerDatePickerMode, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        guard mode.hasDate else { return time }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let dayText: String
        if day == today { dayText = "今天" }
        else if day == calendar.date(byAdding: .day, value: 1, to: today) { dayText = "明天" }
        else {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "M月d日 EEE" : "yyyy年M月d日 EEE"
            dayText = f.string(from: date)
        }
        return mode.hasTime ? "\(dayText) \(time)" : dayText
    }

    static func monthTitle(_ month: Date, calendar: Calendar = .current) -> String {
        "\(calendar.component(.year, from: month))年\(calendar.component(.month, from: month))月"
    }
}

/// Deadliner 风格的日期 / 时间选择：圆角胶囊字段，点开后是快捷选项、月历和时间行。
struct DeadlinerDatePicker: View {
    @Binding var selection: Date?
    var components: DeadlinerDatePickerMode
    var bounds: DatePickerBounds
    var allowsNone: Bool
    var defaultValue: () -> Date
    @State private var isOpen = false
    @Environment(\.palette) private var t

    /// 可选值：面板里多一个「不设时间」。
    init(selection: Binding<Date?>, components: DeadlinerDatePickerMode = .dateAndTime, in bounds: DatePickerBounds = .unbounded,
         defaultValue: @escaping () -> Date = { Date() }) {
        _selection = selection
        self.components = components
        self.bounds = bounds
        self.allowsNone = true
        self.defaultValue = defaultValue
    }

    init(selection: Binding<Date>, components: DeadlinerDatePickerMode = .dateAndTime, in bounds: DatePickerBounds = .unbounded) {
        _selection = Binding(get: { selection.wrappedValue }, set: { if let value = $0 { selection.wrappedValue = value } })
        self.components = components
        self.bounds = bounds
        self.allowsNone = false
        let current = selection.wrappedValue
        self.defaultValue = { current }
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: components == .time ? "clock" : "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(t.primary)
                Text(selection.map { DeadlinerDateMath.label($0, mode: components) } ?? "未设置")
                    .foregroundStyle(selection == nil ? t.onSurfaceVariant : t.onSurface)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(t.primary.opacity(isOpen ? (t.isDark ? 0.30 : 0.18) : (t.isDark ? 0.18 : 0.09)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selection.map { DeadlinerDateMath.label($0, mode: components) } ?? "未设置")
        .accessibilityHint("选择日期")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            DeadlinerDatePickerPanel(selection: $selection, components: components, bounds: bounds,
                                     allowsNone: allowsNone, defaultValue: defaultValue) { isOpen = false }
                .deadlinerTheme()
        }
    }
}

/// 弹出面板本体。改动即时写回；回车完成，Esc 关闭。
struct DeadlinerDatePickerPanel: View {
    @Binding var selection: Date?
    let components: DeadlinerDatePickerMode
    let bounds: DatePickerBounds
    let allowsNone: Bool
    let defaultValue: () -> Date
    var now: Date = Date()
    var close: () -> Void
    @State private var month: Date
    @State private var timeText: String
    @FocusState private var timeFocused: Bool
    @Environment(\.palette) private var t

    init(selection: Binding<Date?>, components: DeadlinerDatePickerMode, bounds: DatePickerBounds, allowsNone: Bool,
         defaultValue: @escaping () -> Date, now: Date = Date(), close: @escaping () -> Void) {
        _selection = selection
        self.components = components
        self.bounds = bounds
        self.allowsNone = allowsNone
        self.defaultValue = defaultValue
        self.now = now
        self.close = close
        let shown = selection.wrappedValue ?? DeadlinerDateMath.clamp(defaultValue(), to: bounds, mode: components)
        _month = State(initialValue: DeadlinerDateMath.monthStart(shown))
        _timeText = State(initialValue: selection.wrappedValue.map { Self.timeString($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if components.hasDate || allowsNone {
                HStack(spacing: 6) {
                    if components.hasDate {
                        ForEach(DeadlinerDateMath.QuickDay.allCases, id: \.self) { quick in
                            let day = DeadlinerDateMath.day(quick, now: now)
                            PickerChip(title: quick.title, selected: isSelected(day)) { pick(day) }
                                .disabled(!DeadlinerDateMath.isSelectable(day, bounds: bounds))
                        }
                    }
                    if allowsNone {
                        PickerChip(title: "不设时间", selected: false, tint: t.onSurfaceVariant) { selection = nil; close() }
                    }
                }
            }
            if components.hasDate {
                DeadlinerMonthGrid(month: month, today: now, bounds: bounds,
                                   isEndpoint: { isSelected($0) }, onPage: { month = DeadlinerDateMath.shiftMonth(month, by: $0) },
                                   onPick: pick)
            }
            if components.hasTime { timeRow }
            HStack {
                Text(selection.map { DeadlinerDateMath.label($0, mode: components, now: now) } ?? "未设置")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("完成") { commitTime(); close() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 332)
        .onExitCommand(perform: close)
        .onChange(of: timeFocused) { if !timeFocused { commitTime() } }
        .onChange(of: selection) { if !timeFocused { timeText = selection.map { Self.timeString($0) } ?? "" } }
    }

    private var timeRow: some View {
        HStack(spacing: 6) {
            ForEach(DeadlinerDateMath.commonTimes, id: \.hour) { time in
                let current = selection.map { (Calendar.current.component(.hour, from: $0), Calendar.current.component(.minute, from: $0)) }
                PickerChip(title: String(format: "%d:%02d", time.hour, time.minute),
                           selected: current.map { $0 == (time.hour, time.minute) } ?? false) {
                    setTime(time.hour, time.minute)
                }
            }
            Spacer(minLength: 4)
            TextField("时:分", text: $timeText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .font(.callout.weight(.medium))
                .frame(width: 52, height: 26)
                .background(t.fieldBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(timeFocused ? t.primary : .clear, lineWidth: 1.5))
                .focused($timeFocused)
                .onSubmit { commitTime(); close() }
                .accessibilityLabel("时间，时:分")
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        selection.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
    }

    private func pick(_ day: Date) {
        let base = selection ?? defaultValue()
        selection = DeadlinerDateMath.clamp(DeadlinerDateMath.combine(day: day, time: base), to: bounds, mode: components)
        month = DeadlinerDateMath.monthStart(day)
        if components == .date { close() }
    }

    private func setTime(_ hour: Int, _ minute: Int) {
        let base = selection ?? defaultValue()
        selection = DeadlinerDateMath.clamp(DeadlinerDateMath.setTime(hour: hour, minute: minute, on: base), to: bounds, mode: components)
        timeText = selection.map { Self.timeString($0) } ?? ""
    }

    /// 把输入框里的文字写回；无法解析时恢复原值。
    private func commitTime() {
        guard components.hasTime else { return }
        if let parsed = DeadlinerDateMath.parseTime(timeText) {
            setTime(parsed.hour, parsed.minute)
        } else {
            timeText = selection.map { Self.timeString($0) } ?? ""
        }
    }

    private static func timeString(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}

/// 月历：周一开头的圆角日期格，今天描边、选中填充主题色，可另外标出范围。
struct DeadlinerMonthGrid: View {
    let month: Date
    var today: Date = Date()
    var bounds: DatePickerBounds = .unbounded
    var isEndpoint: (Date) -> Bool
    var isInRange: (Date) -> Bool = { _ in false }
    var showsPrevious = true
    var showsNext = true
    var onPage: (Int) -> Void
    var onPick: (Date) -> Void
    @Environment(\.palette) private var t

    var body: some View {
        let calendar = DeadlinerDateMath.mondayFirst()
        VStack(spacing: 6) {
            HStack {
                pageButton(-1, symbol: "chevron.left", help: "上个月").opacity(showsPrevious ? 1 : 0).disabled(!showsPrevious || !canPage(-1))
                Spacer()
                Text(DeadlinerDateMath.monthTitle(month)).font(.headline).monospacedDigit()
                Spacer()
                pageButton(1, symbol: "chevron.right", help: "下个月").opacity(showsNext ? 1 : 0).disabled(!showsNext || !canPage(1))
            }
            HStack(spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            let weeks = DeadlinerDateMath.monthGrid(for: month, calendar: calendar)
            ForEach(weeks.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { weekday in
                        if let day = weeks[index][weekday] { cell(day, calendar: calendar) }
                        else { Color.clear.frame(maxWidth: .infinity).frame(height: 30) }
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, calendar: Calendar) -> some View {
        let selected = isEndpoint(day)
        let inRange = !selected && isInRange(day)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let enabled = DeadlinerDateMath.isSelectable(day, bounds: bounds, calendar: calendar)
        let fill: Color = selected ? t.primary : inRange ? t.primary.opacity(t.isDark ? 0.30 : 0.16) : t.primary.opacity(0.04)
        return Button { onPick(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.callout.monospacedDigit().weight(selected || isToday ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : isToday ? t.primary : t.onSurface)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(fill, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(isToday && !selected ? t.primary : .clear, lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(DeadlinerDateMath.label(day, mode: .date, now: today))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pageButton(_ offset: Int, symbol: String, help: String) -> some View {
        Button { onPage(offset) } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(t.primary)
                .frame(width: 26, height: 26)
                .background(t.primary.opacity(t.isDark ? 0.18 : 0.09), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// 翻过去的月份里至少要有一天可选。
    private func canPage(_ offset: Int) -> Bool {
        let target = DeadlinerDateMath.shiftMonth(month, by: offset)
        if offset < 0, let lower = bounds.lower {
            let lastDay = DeadlinerDateMath.shiftMonth(target, by: 1).addingTimeInterval(-1)
            return lastDay >= Calendar.current.startOfDay(for: lower)
        }
        if offset > 0, let upper = bounds.upper { return target <= upper }
        return true
    }
}

/// 面板里的小胶囊，样式同分类选择标签。
private struct PickerChip: View {
    let title: String
    let selected: Bool
    var tint: Color?
    var action: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        let color = tint ?? t.primary
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(selected ? Color.white : color)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(selected ? color : color.opacity(t.isDark ? 0.22 : 0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
