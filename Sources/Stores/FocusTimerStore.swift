import Foundation
import Observation
import Shared
import SwiftUI
import UserNotifications

/// 专注计时。开始、暂停、结束、结束并完成任务、习惯计时与打卡等规则都在 Core
/// （`IosFocusTimerStateBridge` / FocusTimerViewModel），与 iOS、Android 相同。
/// 正在进行的计时只保存在这台 Mac 上；结束后的专注记录随同步到其他设备。
@MainActor
@Observable
final class FocusTimerStore {
    /// 正在进行的计时。
    struct Running: Equatable {
        let sessionId: String
        let targetId: String
        let isHabit: Bool
        let title: String
        let isCountdown: Bool
        let isRunning: Bool
        let elapsedSeconds: Int
        let remainingSeconds: Int?
        let plannedSeconds: Int?
        let canPause: Bool
        let canResume: Bool
        let canFinish: Bool
        let canFinishAndComplete: Bool
        let canFinishAndRecord: Bool
        let habit: HabitContext?

        /// 倒计时显示剩余时间，正计时显示已用时间。
        var displaySeconds: Int { remainingSeconds ?? elapsedSeconds }

        /// 倒计时已过去的比例；正计时为 nil。
        var progress: Double? {
            guard let plannedSeconds, plannedSeconds > 0 else { return nil }
            return min(1, Double(elapsedSeconds) / Double(plannedSeconds))
        }
    }

    /// 习惯计时结束时打卡用的信息。
    struct HabitContext: Equatable {
        let name: String
        let isQuantity: Bool
        let unit: String?
        let completed: Int
        let target: Int
        let canRecord: Bool
        let updatedAt: String
    }

    /// 刚结束的一次专注（计时窗显示结果，直到关闭或开始下一次）。
    struct Result: Equatable {
        let sessionId: String
        let title: String
        let seconds: Int
        let isHabit: Bool
        let recordedHabit: Bool
        let canCompleteTask: Bool
        let taskCompleted: Bool
    }

    private(set) var running: Running?
    private(set) var result: Result?
    private(set) var warning: String?
    private(set) var errorMessage: String?
    private(set) var isBusy = false
    /// Core 已经读完初始状态（之前的计时已核对）。
    private(set) var isLoaded = false
    private(set) var todaySeconds = 0
    /// 编辑器中正在查看的任务的专注统计。
    private(set) var selectedTaskId: String?
    private(set) var selectedTaskTodaySeconds = 0
    private(set) var selectedTaskTotalSeconds = 0

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private let alarm: FocusAlarmPort
    @ObservationIgnored private let didRecord: () -> Void
    @ObservationIgnored private var bridge: IosFocusTimerStateBridge?
    @ObservationIgnored private var ticker: Timer?
    /// 上一次看到的「刚结束的专注」；启动时已有的那条不再显示结果。
    @ObservationIgnored private var seenCompletedSession: String??
    @ObservationIgnored private var seenTaskState: String?
    /// 发出命令后，下一次不忙的状态里的 outcome 才是这次命令的结果。
    @ObservationIgnored private var awaitingOutcome = false

    init(database: DeadlinerDatabase, alarm: FocusAlarmPort, didRecord: @escaping () -> Void) {
        self.database = database
        self.alarm = alarm
        self.didRecord = didRecord
    }

    func start() {
        guard bridge == nil else { return }
        let bridge = IosFocusTimerStateBridge(database: database, alarmPort: alarm)
        self.bridge = bridge
        bridge.start { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }
    }

    /// 应用回到前台或数据同步后：重新核对计时（倒计时可能已经结束）。
    func reconcile() { bridge?.reconcile() }

    /// 退出前调用。Core 在后台线程读写数据库：最多等半秒让正在执行的命令完成，再关闭桥接（之后数据库才关闭）。
    func stop() {
        let deadline = Date().addingTimeInterval(0.5)
        while isBusy, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        ticker?.invalidate()
        ticker = nil
        bridge?.close()
        bridge = nil
    }

    // MARK: - 命令

    /// 开始专注任务；`minutes` 为 nil 时正计时。
    func startTask(_ taskId: String, minutes: Int?) {
        command {
            if let minutes { $0.startCountdown(taskUid: taskId, plannedDurationSeconds: Int64(minutes * 60)) }
            else { $0.startStopwatch(taskUid: taskId) }
        }
    }

    func startHabit(_ habitId: String, minutes: Int?) {
        command {
            if let minutes { $0.startHabitCountdown(habitUid: habitId, plannedDurationSeconds: Int64(minutes * 60)) }
            else { $0.startHabitStopwatch(habitUid: habitId) }
        }
    }

    func pause() { command { $0.pause() } }
    func resume() { command { $0.resume() } }
    func finish() { command { $0.finish() } }
    func finishAndCompleteTask() { command { $0.finishAndCompleteTask() } }
    func discard() { command { $0.discard() } }

    /// 结束习惯计时并打卡；计量习惯传入数量。
    func finishAndRecordHabit(amount: Int?) {
        guard let running, let habit = running.habit else { return }
        command {
            $0.finishAndRecordHabit(sessionUid: running.sessionId, amount: amount.map { KotlinInt(int: Int32($0)) },
                                    expectedHabitUpdatedAt: habit.updatedAt)
        }
    }

    /// 结果页的「完成任务」：把刚保存的专注对应的任务标记为完成。
    func completeSavedTask() {
        guard let result else { return }
        command { $0.completeSavedTask(sessionUid: result.sessionId) }
    }

    func dismissResult() {
        result = nil
        errorMessage = nil
    }

    /// 编辑器打开某个任务时读取它的专注统计。
    func selectTask(_ taskId: String?) {
        selectedTaskId = taskId
        bridge?.selectTask(taskUid: taskId)
    }

    /// 任务正在计时、又要完成 / 放弃 / 归档 / 删除时：先结束并保存这次专注，再执行操作（Core 在同一事务里完成）。
    func resolveTaskChange(_ taskId: String, action: TaskAction?, delete: Bool, completion: @escaping (String?) -> Void) {
        guard let bridge, let running, running.targetId == taskId, !running.isHabit else { return completion(nil) }
        bridge.resolveConfirmedChange(targetUid: taskId, habit: false, delete: delete, taskAction: action,
                                      sessionUid: running.sessionId) { [weak self] outcome in
            MainActor.assumeIsolated {
                self?.didRecord()
                completion(Self.message(for: outcome.name))
            }
        }
    }

    /// 习惯正在计时、又要归档或删除时：先结束这次专注，再执行操作。
    func resolveHabitChange(_ habitId: String, delete: Bool, completion: @escaping (String?) -> Void) {
        guard let bridge, let running, running.targetId == habitId, running.isHabit else { return completion(nil) }
        bridge.resolveConfirmedChange(targetUid: habitId, habit: true, delete: delete, taskAction: nil,
                                      sessionUid: running.sessionId) { [weak self] outcome in
            MainActor.assumeIsolated {
                self?.didRecord()
                completion(Self.message(for: outcome.name))
            }
        }
    }

    /// 这个习惯是否正在计时（Core 不允许直接归档或删除正在计时的习惯）。
    func isTiming(habit habitId: String) -> Bool { running.map { $0.isHabit && $0.targetId == habitId } ?? false }

    /// 忙碌时的重复命令由 Core 忽略（FocusTimerViewModel 自己判断），这里不拦截。
    private func command(_ body: (IosFocusTimerStateBridge) -> Void) {
        guard let bridge else { return }
        errorMessage = nil
        result = nil
        awaitingOutcome = true
        body(bridge)
    }

    // MARK: - 状态

    private func apply(_ state: FocusTimerUiState) {
        isBusy = state.isBusy
        if !state.isLoading { isLoaded = true }
        todaySeconds = Int(state.todayDurationSeconds)
        if state.selectedTaskUid == selectedTaskId {
            selectedTaskTodaySeconds = Int(state.selectedTaskTodayDurationSeconds)
            selectedTaskTotalSeconds = Int(state.selectedTaskTotalDurationSeconds)
        }
        running = state.timer.map(Self.running)
        warning = (state.timer?.warning ?? state.warning).map { Self.warningText($0.name) }
        if let error = state.error, !error.isEmpty { errorMessage = error }
        if awaitingOutcome, !state.isBusy, !state.isLoading {
            awaitingOutcome = false
            if let outcome = state.lastOutcome, let message = Self.message(for: outcome.name) { errorMessage = message }
        }
        applyCompleted(state)
        updateTicker()
    }

    /// 新结束的专注：显示结果，并让列表、专注记录和统计刷新。
    private func applyCompleted(_ state: FocusTimerUiState) {
        let session = state.lastCompletedSession
        let taskState = state.lastCompletedTaskState?.name
        guard let seen = seenCompletedSession else {
            // 第一次收到状态：记下已有的，不当作新结果。
            if !state.isLoading { seenCompletedSession = .some(session?.uid); seenTaskState = taskState }
            return
        }
        guard session?.uid != seen || taskState != seenTaskState else { return }
        seenCompletedSession = .some(session?.uid)
        seenTaskState = taskState
        didRecord()
        guard let session else { return }
        result = Result(
            sessionId: session.uid,
            title: session.targetTitleSnapshot,
            seconds: Int(session.durationSeconds),
            isHabit: session.boundTarget.kind.name == "HABIT",
            recordedHabit: session.habitRecordedAmount != nil || session.habitOccurredOn != nil,
            canCompleteTask: state.canCompleteLastTask,
            taskCompleted: taskState == "COMPLETED"
        )
    }

    /// 计时进行中每秒让 Core 重新计算显示时间（不写数据库）；倒计时到点由 Core 自动结束。
    private func updateTicker() {
        if running?.isRunning == true {
            guard ticker == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.bridge?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private static func running(_ s: FocusTimerSnapshot) -> Running {
        let habit = s.habitRecordContext.map {
            HabitContext(name: $0.name, isQuantity: $0.trackingMode.name == "QUANTITY", unit: $0.unit,
                         completed: Int($0.completedCount), target: Int($0.targetCount), canRecord: $0.canRecord,
                         updatedAt: $0.habitUpdatedAt)
        }
        let isHabit = s.target?.kind.name == "HABIT"
        return Running(
            sessionId: s.sessionUid,
            targetId: s.target?.uid ?? s.taskUid,
            isHabit: isHabit,
            title: s.taskTitle,
            isCountdown: s.mode.name == "COUNTDOWN",
            isRunning: s.state.name == "RUNNING",
            elapsedSeconds: Int(s.elapsedSeconds),
            remainingSeconds: s.remainingSeconds.map { Int(truncating: $0) },
            plannedSeconds: s.plannedDurationSeconds.map { Int(truncating: $0) },
            canPause: s.canPause,
            canResume: s.canResume,
            canFinish: s.canFinish,
            canFinishAndComplete: s.canFinishAndComplete,
            canFinishAndRecord: s.canFinishAndRecord,
            habit: habit
        )
    }

    // MARK: - 文案

    static func message(for outcome: String) -> String? {
        switch outcome {
        case "APPLIED", "NO_OP": nil
        case "TASK_REQUIRED": "请选择要专注的任务"
        case "TASK_NOT_FOUND": "任务不存在，可能已在其他设备上删除"
        case "TASK_NOT_ACTIVE": "只有进行中的任务可以开始专注"
        case "TIMER_ALREADY_ACTIVE": "已经有一个正在进行的专注，请先结束它"
        case "TIMER_NOT_FOUND": "这次专注已经结束"
        case "TIMER_REQUIRES_RESOLUTION": "请先结束正在进行的专注"
        case "INVALID_DURATION": "专注时长无效"
        case "CLOCK_ANOMALY": "系统时间发生了变化，请检查时间设置后重试"
        case "HABIT_NOT_FOUND": "习惯不存在，可能已在其他设备上删除"
        case "HABIT_NOT_ACTIVE": "只有进行中的习惯可以开始专注"
        case "HABIT_NOT_DUE": "这个习惯今天不需要打卡"
        case "HABIT_INVALID_AMOUNT": "打卡数量无效"
        default: "当前状态下不能执行这个操作"
        }
    }

    static func warningText(_ warning: String) -> String {
        switch warning {
        case "CLOCK_ANOMALY": "系统时间发生了变化，计时可能不准确"
        case "LONG_RUNNING": "已经专注很久了，记得结束计时"
        case "EXCESSIVE_DURATION": "这次计时过长，是否忘记结束了？"
        case "ALARM_UNAVAILABLE": "无法安排倒计时结束提醒，请在设置中开启通知"
        default: "计时状态异常"
        }
    }

    /// `1:05:09` / `25:00`。
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let (h, m, sec) = (s / 3600, s % 3600 / 60, s % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

/// 倒计时结束提醒：Core 在开始、暂停、继续、结束时调用（在后台线程）。
/// 使用独立的标识前缀，不会被任务 / 习惯提醒的重新排程清掉。
final class FocusAlarmScheduler: NSObject, FocusAlarmPort, @unchecked Sendable {
    static let prefix = "focus-timer."

    func scheduleCountdown(sessionUid: String, fireAt: String, taskTitle: String) -> FocusAlarmResult {
        guard UserDefaults.standard.bool(forKey: NotificationSettings.enabledKey) else {
            return FocusAlarmResult(succeeded: false, failureMessage: "通知未开启")
        }
        guard let date = CoreDates.parseInstant(fireAt) else {
            return FocusAlarmResult(succeeded: false, failureMessage: "提醒时间无效")
        }
        let content = UNMutableNotificationContent()
        content.title = "专注结束"
        content.body = "「\(taskTitle)」的倒计时已经结束"
        content.sound = .default
        content.userInfo = ["ownerUid": sessionUid, "kind": "FOCUS_TIMER"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.prefix + sessionUid, content: content, trigger: trigger))
        return FocusAlarmResult(succeeded: true, failureMessage: nil)
    }

    func cancelCountdown(sessionUid: String) -> FocusAlarmResult {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.prefix + sessionUid])
        return FocusAlarmResult(succeeded: true, failureMessage: nil)
    }
}

extension EnvironmentValues {
    /// 专注计时（主窗口、计时窗与菜单栏面板共用）；测试与预览中为 nil。
    @Entry var focusTimer: FocusTimerStore?
}
