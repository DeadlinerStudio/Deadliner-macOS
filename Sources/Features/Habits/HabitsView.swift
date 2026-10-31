import SwiftUI

/// 习惯页：所选日期的完成度圆环 + 一周日期条 + 分组的习惯卡片。
struct HabitsView: View {
    @Bindable var store: HabitListStore
    let categories: [String: CategoryItem]

    var body: some View {
        HabitsContent(
            daily: store.filtered(store.dailyHabits),
            period: store.filtered(store.periodGoals),
            upcoming: store.filtered(store.upcomingReviews),
            week: store.week,
            selectedDate: store.selectedDate,
            categories: categories,
            isLoading: store.isLoading,
            errorMessage: store.errorMessage,
            searchText: $store.searchText,
            onSelectDate: store.select(date:),
            onPrimaryAction: store.applyPrimaryAction
        )
    }
}

/// 不依赖 Core 的页面主体，便于截图测试。
struct HabitsContent: View {
    let daily: [HabitItem]
    let period: [HabitItem]
    let upcoming: [HabitItem]
    let week: [HabitDay]
    let selectedDate: String
    let categories: [String: CategoryItem]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var searchText: String
    var onSelectDate: ((String) -> Void)?
    var onPrimaryAction: ((HabitItem) -> Void)?
    @Environment(\.miuix) private var t

    private var selectedDay: HabitDay? { week.first { $0.date == selectedDate } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    overview
                    if let errorMessage {
                        Text("读取习惯失败：\(errorMessage)").font(.callout).foregroundStyle(t.error)
                    }
                    if daily.isEmpty && period.isEmpty && upcoming.isEmpty && !isLoading {
                        emptyState
                    }
                    section("今日习惯", daily)
                    section("周期目标", period)
                    section("即将复习", upcoming)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.pageBg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("习惯")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(t.onSurface)
                if let day = selectedDay {
                    Text("\(HabitDates.isToday(selectedDate) ? "今日" : HabitDates.monthDay(selectedDate)) \(day.completed)/\(day.total)")
                        .font(.system(size: 13))
                        .foregroundStyle(t.onSurfaceVariant)
                }
                Spacer()
            }
            SearchPill(text: $searchText, placeholder: "搜索习惯")
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var overview: some View {
        HStack(spacing: 28) {
            ProgressRing(fraction: selectedDay?.fraction ?? 0, size: 92)
            HStack(spacing: 6) {
                ForEach(week) { day in
                    WeekDayCell(day: day, selected: day.date == selectedDate) { onSelectDate?(day.date) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(t.groupBg, in: RoundedRectangle(cornerRadius: MiuixRadius.group, style: .continuous))
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [HabitItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.onSurfaceVariant)
                    .padding(.leading, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: MiuixCard.minColumnWidth), spacing: MiuixCard.gap)], spacing: MiuixCard.gap) {
                    ForEach(items) { habit in
                        HabitCard(habit: habit, category: habit.categoryId.flatMap { categories[$0] }) {
                            onPrimaryAction?(habit)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "target").font(.system(size: 36))
            Text(searchText.isEmpty ? "这一天没有需要打卡的习惯" : "没有找到匹配的习惯").font(.callout)
        }
        .foregroundStyle(t.onSurfaceVariant)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// 习惯卡片：与任务卡片同样的 76 高、24 圆角；进度条显示目标完成比例。
struct HabitCard: View {
    let habit: HabitItem
    let category: CategoryItem?
    var onPrimaryAction: (() -> Void)?
    @Environment(\.miuix) private var t
    @State private var hovering = false

    var body: some View {
        // 习惯的进度条始终用主题色，完成状态由左侧对勾表示（满格的 Secondary 色过重）。
        let colors = IndicatorStatus.undergo.colors(t)
        HStack(spacing: 10) {
            Button { onPrimaryAction?() } label: { actionIcon }
                .buttonStyle(.plain)
                .disabled(!habit.canApplyPrimaryAction || onPrimaryAction == nil)
                .help(HabitTexts.actionHelp(habit))

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(habit.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(t.onSurface)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(HabitTexts.side(habit))
                        .font(.system(size: 12))
                        .foregroundStyle(t.onSurface.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let category { CategoryChip(category: category) }
                    CountPill(text: HabitTexts.progress(habit))
                    Text(habit.note)
                        .font(.system(size: 12))
                        .foregroundStyle(t.onSurfaceVariant)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, MiuixCard.padX)
        .padding(.vertical, MiuixCard.padY)
        .frame(height: MiuixCard.height)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    colors.base
                    colors.overlay
                    if habit.progress > 0 {
                        LinearGradient(colors: [colors.indicatorStart, colors.indicator], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * habit.progress)
                            .animation(.easeOut(duration: 0.5), value: habit.progress)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MiuixRadius.card, style: .continuous))
        .opacity(habit.isDue ? 1 : 0.7)
        .shadow(color: .black.opacity(t.isDark ? 0 : (hovering ? 0.08 : 0.04)), radius: hovering ? 7 : 1, y: hovering ? 4 : 1)
        .offset(y: hovering ? -1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var actionIcon: some View {
        let enabled = habit.canApplyPrimaryAction
        if habit.actionKind == .addQuantity && !habit.isCompleted {
            Text("+\(habit.actionAmount)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Color.white : t.onSurfaceVariant)
                .frame(width: 30, height: 22)
                .background(enabled ? t.primary : t.onSurfaceVariant.opacity(0.2), in: Capsule())
        } else {
            Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21))
                .foregroundStyle(habit.isCompleted ? t.completedCheck : t.onSurfaceVariant.opacity(enabled ? 0.9 : 0.35))
        }
    }
}

/// 完成度圆环。
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 92
    @Environment(\.miuix) private var t

    var body: some View {
        ZStack {
            Circle().stroke(t.segmentedBg, lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(t.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: fraction)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(t.onSurface)
        }
        .frame(width: size, height: size)
    }
}

/// 一周日期条中的一天：星期、日期，以及当天完成度的小圆环。
private struct WeekDayCell: View {
    let day: HabitDay
    let selected: Bool
    var action: () -> Void
    @Environment(\.miuix) private var t

    var body: some View {
        let today = HabitDates.isToday(day.date)
        Button(action: action) {
            VStack(spacing: 6) {
                Text(HabitDates.weekday(day.date))
                    .font(.system(size: 11.5, weight: today ? .semibold : .regular))
                    .foregroundStyle(today ? t.primary : t.onSurfaceVariant)
                ZStack {
                    Circle().fill(selected ? t.primary : Color.clear)
                    Circle()
                        .trim(from: 0, to: selected ? 0 : day.fraction)
                        .stroke(t.primary.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(HabitDates.dayOfMonth(day.date))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(selected ? .white : t.onSurface)
                }
                .frame(width: 36, height: 36)
            }
            .frame(width: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 习惯日期（`yyyy-MM-dd`，本地日期）的显示。
enum HabitDates {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(_ raw: String) -> Date? { parser.date(from: raw) }
    static func string(_ date: Date) -> String { parser.string(from: date) }
    static func isToday(_ raw: String) -> Bool { raw == string(Date()) }

    static func weekday(_ raw: String) -> String {
        guard let date = date(raw) else { return "" }
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: date) - 1]
    }

    static func dayOfMonth(_ raw: String) -> String {
        guard let date = date(raw) else { return "" }
        return String(Calendar.current.component(.day, from: date))
    }

    static func monthDay(_ raw: String) -> String {
        guard let date = date(raw) else { return raw }
        let calendar = Calendar.current
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }
}
