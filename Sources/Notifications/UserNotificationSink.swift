import Foundation
import UserNotifications

/// 系统通知中心里本应用用到的三个操作；测试中用内存实现代替。
protocol PendingNotificationCenter: AnyObject, Sendable {
    func pendingRequests(_ completion: @escaping @Sendable ([UNNotificationRequest]) -> Void)
    func remove(_ identifiers: [String])
    func add(_ request: UNNotificationRequest)
}

final class SystemNotificationCenter: PendingNotificationCenter, @unchecked Sendable {
    static let shared = SystemNotificationCenter()
    private var center: UNUserNotificationCenter { .current() }

    func pendingRequests(_ completion: @escaping @Sendable ([UNNotificationRequest]) -> Void) {
        center.getPendingNotificationRequests { completion($0) }
    }

    func remove(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) { center.add(request) }
}

/// 把 Core 算出的提醒同步到系统通知中心。只管理带 `deadliner.` 前缀的请求。
///
/// Core 每次数据库提交后都会重算，应用激活、定时刷新也会触发，短时间内常有多次：
/// - 合并：`coalesceDelay` 内的多次调用只按最后一次执行；
/// - 串行：上一次与系统通知中心的比对完成后才开始下一次，旧的计划不会晚到并覆盖新的；
/// - 只改有变化的：与已排的请求逐条比较（时间、标题、正文、类型），没变的不重新添加。
final class UserNotificationSink: NotificationSink, @unchecked Sendable {
    /// 系统对每个应用待发送的通知数量有上限，只保留最近的这些。
    static let limit = 60
    static let prefix = "deadliner."

    private let center: PendingNotificationCenter
    private let coalesceDelay: TimeInterval
    private let queue = DispatchQueue(label: "com.deadliner.macos.notification-sink")
    // 以下状态只在 `queue` 上读写。
    private var latest: [PlannedNotification]?
    private var flushScheduled = false
    private var inFlight = false
    private var onIdle: [() -> Void] = []

    init(center: PendingNotificationCenter = SystemNotificationCenter.shared, coalesceDelay: TimeInterval = 0.5) {
        self.center = center
        self.coalesceDelay = coalesceDelay
    }

    func replaceAll(with notifications: [PlannedNotification]) {
        queue.async { self.latest = notifications; self.scheduleFlush() }
    }

    func removeAll() {
        queue.async { self.latest = []; self.scheduleFlush() }
    }

    /// 等所有已提交的计划都写入系统后回调（测试使用）。
    func whenIdle(_ completion: @escaping () -> Void) {
        queue.async {
            if !self.inFlight && !self.flushScheduled && self.latest == nil { completion() } else { self.onIdle.append(completion) }
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled, !inFlight else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + coalesceDelay) {
            self.flushScheduled = false
            self.flush()
        }
    }

    private func flush() {
        guard !inFlight, let plan = latest else { return }
        latest = nil
        inFlight = true
        // 请求对象创建后不再修改，只在比对回调里读取。
        nonisolated(unsafe) let desired = Self.requests(for: plan, now: Date())
        let center = center
        center.pendingRequests { pending in
            let changes = Self.diff(pending: pending, desired: desired)
            center.remove(changes.remove)
            changes.add.forEach(center.add)
            Diagnostics.notifications.debug(
                "replan desired=\(desired.count, privacy: .public) added=\(changes.add.count, privacy: .public) removed=\(changes.remove.count, privacy: .public)")
            self.queue.async {
                self.inFlight = false
                if self.latest != nil {
                    self.scheduleFlush()
                } else {
                    let waiting = self.onIdle
                    self.onIdle = []
                    waiting.forEach { $0() }
                }
            }
        }
    }

    // MARK: - 计算（纯函数，便于测试）

    struct Changes {
        var remove: [String] = []
        var add: [UNNotificationRequest] = []
    }

    static func requests(for plan: [PlannedNotification], now: Date) -> [UNNotificationRequest] {
        plan.filter { $0.fireAt > now }
            .sorted { $0.fireAt < $1.fireAt }
            .prefix(limit)
            .map { item in
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.userInfo = ["ownerUid": item.ownerUid, "kind": item.kind]
                content.categoryIdentifier = TaskNotificationActions.category(forKind: item.kind)
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireAt)
                return UNNotificationRequest(identifier: item.id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            }
    }

    static func diff(pending: [UNNotificationRequest], desired: [UNNotificationRequest]) -> Changes {
        let wanted = Set(desired.map(\.identifier))
        let existing = Dictionary(pending.filter { $0.identifier.hasPrefix(prefix) }.map { ($0.identifier, $0) },
                                  uniquingKeysWith: { first, _ in first })
        var changes = Changes()
        changes.remove = existing.keys.filter { !wanted.contains($0) }.sorted()
        changes.add = desired.filter { request in
            guard let current = existing[request.identifier] else { return true }
            return signature(current) != signature(request)
        }
        return changes
    }

    /// 判断两个请求是否相同：触发时间（到秒）、标题、正文、按钮类别、类型与所属任务。
    static func signature(_ request: UNNotificationRequest) -> String {
        let c = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
        let time = [c?.year, c?.month, c?.day, c?.hour, c?.minute, c?.second].map { $0.map(String.init) ?? "-" }.joined(separator: ".")
        let info = request.content.userInfo
        return [time, request.content.title, request.content.body, request.content.categoryIdentifier,
                info["kind"] as? String ?? "", info["ownerUid"] as? String ?? ""].joined(separator: "\u{1F}")
    }
}
