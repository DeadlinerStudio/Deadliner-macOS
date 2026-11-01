import AppKit
import Shared
import UserNotifications

/// 把 Core 的通知编排接到系统通知中心：数据库提交（包括同步合并）后 Core 自动重新计算提醒；
/// 另外在应用激活、通知送达和每 30 分钟时刷新一次，排上习惯的下一次提醒。
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    private let database: DeadlinerDatabase
    private let open: (_ ownerUid: String, _ kind: String) -> Void
    private var timer: Timer?

    init(database: DeadlinerDatabase, open: @escaping (_ ownerUid: String, _ kind: String) -> Void) {
        self.database = database
        self.open = open
        super.init()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        _ = database.configureNotificationUpdates(
            gateway: MacNotificationGateway(sink: UserNotificationSink()),
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
    }

    /// 设置变化后传 `force: true`。
    func refresh(force: Bool = false) {
        database.triggerNotificationInfoUpdate(force: force)
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
        let info = response.notification.request.content.userInfo
        let owner = info["ownerUid"] as? String ?? ""
        let kind = info["kind"] as? String ?? ""
        await MainActor.run {
            refresh()
            open(owner, kind)
        }
    }
}
