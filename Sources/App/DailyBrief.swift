import AppKit
import SwiftUI

/// 每日概览弹窗：每天第一次打开电脑（应用启动、唤醒或解锁）时，以及每天固定的时间，
/// 在所有窗口最上层显示正在进行的任务和今天的习惯。默认关闭，在设置中开启。
enum DailyBriefSettings {
    static let windowId = "daily-brief"
    static let enabledKey = "brief.enabled"
    static let onFirstOpenKey = "brief.onFirstOpen"
    static let fixedTimeKey = "brief.fixedTime"
    static let fixedMinutesKey = "brief.fixedMinutes"
    static let lastFirstOpenKey = "brief.lastFirstOpenDay"
    static let lastFixedKey = "brief.lastFixedDay"
}

/// 判断什么时候弹出。只在应用运行时工作（应用开机自启时，开机即算「第一次打开」）。
@MainActor
final class DailyBriefController {
    /// 打开弹窗；入口还没准备好（主窗口内容尚未出现）时返回 false，下次再试。
    private let show: () -> Bool
    private let defaults: UserDefaults
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, show: @escaping () -> Bool) {
        self.defaults = defaults
        self.show = show
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            })
        }
        // 屏幕解锁。
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
        observers = []
    }

    /// 今天还没因「第一次打开」弹过，或到了固定时间还没弹过，就弹出。
    func check(now: Date = Date()) {
        if let reason = Self.due(defaults: defaults, now: now), show() {
            defaults.set(Self.dayKey(now), forKey: reason)
        }
    }

    /// 应该弹出时返回要记录的键（第一次打开 / 固定时间），否则为 nil。
    static func due(defaults: UserDefaults, now: Date, calendar: Calendar = .current) -> String? {
        guard defaults.bool(forKey: DailyBriefSettings.enabledKey) else { return nil }
        let today = dayKey(now, calendar)
        let firstOpen = defaults.object(forKey: DailyBriefSettings.onFirstOpenKey) as? Bool ?? true
        if firstOpen, defaults.string(forKey: DailyBriefSettings.lastFirstOpenKey) != today {
            return DailyBriefSettings.lastFirstOpenKey
        }
        if defaults.bool(forKey: DailyBriefSettings.fixedTimeKey), defaults.string(forKey: DailyBriefSettings.lastFixedKey) != today {
            let minutes = defaults.object(forKey: DailyBriefSettings.fixedMinutesKey) as? Int ?? 9 * 60
            let fire = calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: now))!
            if now >= fire { return DailyBriefSettings.lastFixedKey }
        }
        return nil
    }

    static func dayKey(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 弹窗内容：任务一组，习惯一组。
struct DailyBriefView: View {
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.palette) private var t

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let tasks = Self.ongoing(model.taskList.tasks, now: context.date)
            let habits = model.habitList.dailyHabits + model.habitList.periodGoals
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日概览").font(.title2.weight(.bold))
                        Text(context.date.formatted(.dateTime.month().day().weekday(.wide))).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        group("正在进行的任务", count: tasks.count, empty: "没有进行中的任务") {
                            ForEach(tasks) { task in
                                let status = TaskStatus.indicator(task, now: context.date)
                                HStack(spacing: 8) {
                                    Circle().fill(status.solid(t)).frame(width: 8, height: 8)
                                    Text(task.title).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(TaskStatus.remainingText(task, now: context.date, detailed: false))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(status == .passed ? t.error : t.onSurfaceVariant)
                                }
                            }
                        }
                        group("今天的习惯", count: habits.count, empty: "今天没有要打卡的习惯") {
                            ForEach(habits) { habit in
                                HStack(spacing: 8) {
                                    Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(habit.isCompleted ? t.completedCheck : t.onSurfaceVariant)
                                    Text(habit.name).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text("\(habit.doneCount)/\(habit.targetCount)\(habit.unit ?? "")")
                                        .font(.caption.monospacedDigit()).foregroundStyle(t.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("打开 Deadliner") {
                        dismissWindow(id: DailyBriefSettings.windowId)
                        (NSApp.delegate as? AppDelegate)?.showMainWindow()
                    }
                    Button("知道了") { dismissWindow(id: DailyBriefSettings.windowId) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 400, height: 480)
            .background(WindowLevelSetter(floating: true))
            .onAppear { model.prepareMenuBarPanel() }
        }
    }

    /// 正在进行：进行中的任务里已经开始的（没有开始时间也算），逾期的排前面，再按截止时间。
    static func ongoing(_ tasks: [TaskItem], now: Date) -> [TaskItem] {
        tasks.filter { $0.state == .active && ($0.startAt.map { $0 <= now } ?? true) }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private func group<Content: View>(_ title: String, count: Int, empty: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(t.onSurfaceVariant)
            }
            if count == 0 {
                Text(empty).font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) { content() }
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(t.groupBg, in: RoundedRectangle(cornerRadius: MiuixRadius.field, style: .continuous))
            }
        }
    }
}
