import AppKit
import Shared
import UserNotifications

/// 把 Core 的通知编排接到系统通知中心：数据库提交（包括同步合并）后 Core 自动重新计算提醒；
/// 另外在应用激活、通知送达和每 30 分钟时刷新一次，排上习惯的下一次提醒。
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    private let database: DeadlinerDatabase
    private let open: (_ ownerUid: String, _ kind: String) -> Void
    /// 通知按钮「完成」「删除」交给任务命令执行（由 AppDelegate 提供）。
    var perform: ((_ action: TaskNotificationActions.Action, _ ownerUid: String) -> Void)?
    private var timer: Timer?
    private var summaryWork: DispatchWorkItem?

    init(database: DeadlinerDatabase, open: @escaping (_ ownerUid: String, _ kind: String) -> Void) {
        self.database = database
        self.open = open
        super.init()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        TaskNotificationActions.register()
        _ = database.configureNotificationUpdates(
            gateway: MacNotificationGateway(sink: UserNotificationSink(), taskReminders: { NotificationSettings.taskReminders() }),
            policyProvider: Self.policyProvider,
            interactionsProvider: Self.interactionsProvider
        )
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // Core 会在任意线程调用这两个回调（例如同步合并在后台线程提交后），
    // 所以它们必须是非隔离的；写在本类的方法里会被当作主线程专用，在后台调用时 Swift 会直接终止应用。
    nonisolated static let policyProvider: @Sendable () -> NotificationPolicy = { NotificationSettings.policy() }
    nonisolated static let interactionsProvider: @Sendable () -> NotificationInteractionState = {
        NotificationInteractionState(taskResults: [], dismissedHabitOccurrences: [])
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        summaryWork?.cancel()
    }

    /// 设置变化后传 `force: true`。
    func refresh(force: Bool = false) {
        database.triggerNotificationInfoUpdate(force: force)
        scheduleDailySummary()
    }

    /// 按当前任务重新排下一条每日摘要（数据变化后由 AppModel 调用）。
    /// 写入、激活、刷新常在同一瞬间先后触发，0.5 秒内的多次只执行最后一次。
    func scheduleDailySummary() {
        summaryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DailySummary.schedule(tasks: self.database.tasks.list().filter { !$0.isDeleted }.map(TaskItem.init(core:)))
            self.pruneSnoozes()
        }
        summaryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// 打开通知开关时请求系统授权；返回是否已获授权。
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        await MainActor.run { refresh() }
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let owner = content.userInfo["ownerUid"] as? String ?? ""
        let kind = content.userInfo["kind"] as? String ?? ""
        let action = TaskNotificationActions.action(for: response.actionIdentifier)
        nonisolated(unsafe) let original = content
        await MainActor.run {
            switch action {
            case .complete?, .delete?:
                if let action, !owner.isEmpty { perform?(action, owner) }
                refresh()
            case .later?:
                snooze(owner, content: original)
            case nil:
                refresh()
                open(owner, kind)
            }
        }
    }

    // MARK: - 稍后提醒

    /// 按剩余时间的一半（至少 1 小时）再提醒一次；任务完成、放弃或删除后自动取消。
    func snooze(_ uid: String, content original: UNNotificationContent, now: Date = Date(),
                center: PendingNotificationCenter = SystemNotificationCenter.shared) {
        guard !uid.isEmpty, let task = database.tasks.find(uid: uid), !task.isDeleted, task.state == .active else { return }
        let hours = TaskNotificationActions.laterDelayHours(dueAt: CoreDates.parseLocal(task.dueAt), now: now)
        guard let content = original.mutableCopy() as? UNMutableNotificationContent else { return }
        content.categoryIdentifier = TaskNotificationActions.categoryId
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600), repeats: false)
        center.add(UNNotificationRequest(identifier: TaskNotificationActions.snoozeId(uid), content: content, trigger: trigger))
        Diagnostics.notifications.info("snoozed task reminder hours=\(hours, privacy: .public)")
    }

    /// 去掉已经不需要的「稍后提醒」（任务已不在进行中或已删除）。
    func pruneSnoozes(center: PendingNotificationCenter = SystemNotificationCenter.shared) {
        center.pendingRequests { [weak self] pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(TaskNotificationActions.snoozePrefix) }
            guard !ids.isEmpty else { return }
            DispatchQueue.main.async {
                guard let database = self?.database else { return }
                let stale = ids.filter { id in
                    let uid = String(id.dropFirst(TaskNotificationActions.snoozePrefix.count))
                    guard let task = database.tasks.find(uid: uid), !task.isDeleted else { return true }
                    return task.state != .active
                }
                center.remove(stale)
            }
        }
    }
}
