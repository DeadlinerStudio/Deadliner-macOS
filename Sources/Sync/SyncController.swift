import AppKit
import Foundation
import Network
import Observation
import Shared

/// 同步的宿主层。同步协议、合并、调度（改动后防抖、回到前台、前台每分钟、失败重试）全部由 Core 的
/// `RepositorySyncCoordinator` 负责；这里只提供配置、生命周期与网络状态，并记录结果。
@MainActor
@Observable
final class SyncController {
    enum Status: Equatable {
        case disabled
        case backingUp
        /// 云端没有同步文件，等待用户确认是否新建（多半是服务器地址不对）。
        case awaitingConfirmation
        case idle
        case syncing
        case succeeded(Date)
        case failed(String)
    }

    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let succeeded: Bool
        let applied: Int
        let message: String?
    }

    /// 同步结果（已从 Kotlin 对象转换，可以安全地跨线程传递）。
    struct Outcome: Sendable {
        let succeeded: Bool
        let applied: Int
        let failure: String?

        init(_ core: WebDavChangeLogSyncOutcome) {
            succeeded = core.succeeded
            applied = Int(core.remoteApplied)
            failure = core.failureMessage
        }
    }

    private(set) var status: Status = .disabled
    private(set) var log: [LogEntry] = []
    private(set) var settings: SyncSettings
    /// 最近一次启用同步前保存的云端备份。
    private(set) var lastBackup: URL?

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private let keychain: KeychainPasswordStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let didApplyRemoteChanges: () -> Void
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var appActive = true
    @ObservationIgnored private var backgroundTimer: Timer?
    @ObservationIgnored private let backupSession: URLSession
    @ObservationIgnored private let backupDirectory: () throws -> URL
    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []
    /// 唤醒后的等待期：此时网络常常还没准备好（例如 VPN 的域名解析），先不同步。
    @ObservationIgnored private var wakeGraceUntil: Date?
    @ObservationIgnored private var wakeTask: DispatchWorkItem?
    @ObservationIgnored private var retryTask: DispatchWorkItem?
    /// 连续的临时网络错误次数。第一次只记录、不显示为失败。
    @ObservationIgnored private var transientFailures = 0

    /// 唤醒后等多久再同步。
    static let wakeGraceSeconds: TimeInterval = 30
    /// 后台遇到临时错误后多久重试一次（前台由 Core 负责重试）。
    static let transientRetrySeconds: TimeInterval = 60

    init(database: DeadlinerDatabase, keychain: KeychainPasswordStore = .init(), defaults: UserDefaults = .standard,
         backupSession: URLSession = .shared, backupDirectory: @escaping () throws -> URL = RemoteBackup.defaultDirectory,
         didApplyRemoteChanges: @escaping () -> Void) {
        self.database = database
        self.keychain = keychain
        self.defaults = defaults
        self.backupSession = backupSession
        self.backupDirectory = backupDirectory
        self.didApplyRemoteChanges = didApplyRemoteChanges
        settings = SyncSettings.load(from: defaults)
    }

    var hasPassword: Bool {
        keychain.password(url: settings.normalizedURL, username: settings.username) != nil
    }

    /// 启动时调用：已启用同步时按保存的设置开始自动同步。
    func start() {
        startNetworkMonitor()
        observeSleep()
        restartBackgroundTimer()
        if settings.enabled { applyConfiguration() }
    }

    /// 保存设置。`password` 为 nil 表示保留钥匙串中已有的密码。
    /// 启用同步时，先把云端同步文件备份到本机，备份成功后才开始同步。
    func save(_ newSettings: SyncSettings, password: String?) throws {
        if newSettings.enabled, let error = newSettings.validationError { throw SyncError.invalid(error) }
        if let password, !password.isEmpty {
            guard keychain.setPassword(password, url: newSettings.normalizedURL, username: newSettings.username) else {
                throw SyncError.invalid("无法把密码保存到钥匙串")
            }
        }
        settings = newSettings
        newSettings.save(to: defaults)
        if newSettings.enabled {
            guard let stored = keychain.password(url: newSettings.normalizedURL, username: newSettings.username) else {
                throw SyncError.invalid("请填写应用密码")
            }
            disable()
            status = .backingUp
            let backup = RemoteBackup(settings: newSettings, password: stored, session: backupSession,
                                      directory: (try? backupDirectory()) ?? FileManager.default.temporaryDirectory)
            _Concurrency.Task {
                do {
                    switch try await backup.run() {
                    case .saved(let file):
                        lastBackup = file
                        applyConfiguration()
                    case .nothingToBackUp:
                        // 不直接开始同步：Core 会在这个位置新建同步文件，而手机可能正用着另一个地址。
                        status = .awaitingConfirmation
                    }
                } catch {
                    status = .failed(error.localizedDescription)
                }
            }
        } else {
            disable()
        }
    }

    /// 用户确认云端确实还没有同步文件，由这台 Mac 新建。
    func confirmCreatingRemoteFile() {
        guard status == .awaitingConfirmation else { return }
        applyConfiguration()
    }

    /// 用户选择先检查地址：关闭同步，不写云端。
    func cancelPendingSync() {
        guard status == .awaitingConfirmation else { return }
        settings.enabled = false
        settings.save(to: defaults)
        disable()
    }

    /// 云端同步文件的完整地址（用于提示）。
    var remoteFileURL: String { settings.normalizedURL + RemoteBackup.remotePath }

    /// 立即同步（「立即同步」按钮、⌘R）。
    func syncNow() {
        guard configured else { return }
        status = .syncing
        _ = database.startSync(trigger: SyncTrigger.manual) { @Sendable outcome in
            let converted = Outcome(outcome)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.record(converted) } }
        }
    }

    func setForeground(_ active: Bool) {
        appActive = active
        guard configured else { return }
        database.setSyncForeground(active: active)
    }

    /// 应用不在前台时的同步间隔（分钟，0 为关闭）。前台时由 Core 负责（改动后、每分钟）。
    func setBackgroundInterval(_ minutes: Int) {
        settings.backgroundInterval = minutes
        settings.save(to: defaults)
        restartBackgroundTimer()
    }

    private func restartBackgroundTimer() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        let minutes = settings.backgroundInterval
        guard minutes > 0 else { return }
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.configured, !self.appActive, !self.inWakeGrace else { return }
                self.startBackgroundSync()
            }
        }
    }

    func stop() {
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sleepObservers = []
        wakeTask?.cancel()
        retryTask?.cancel()
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        monitor?.cancel()
        monitor = nil
        if configured { database.disableAutomaticSync() }
        configured = false
    }

    /// 测试使用：用任意 `SyncBlobTransport`（例如内存实现）代替 WebDAV。
    func configureForTesting(transport: any SyncBlobTransport) {
        database.configureAutomaticTransportSync(transport: transport, onComplete: completionHandler())
        configured = true
        status = .idle
        database.setSyncNetworkAvailable(available: true)
        database.setSyncForeground(active: true)
    }

    // MARK: - Private

    private func applyConfiguration() {
        // 单元测试与正式应用共用同一个 Bundle ID，会读到用户真实的同步设置与钥匙串密码。
        // 测试中绝不连接 WebDAV（内存传输请用 configureForTesting）。
        guard !AppDelegate.isRunningTests else {
            status = .failed("测试运行中，不连接 WebDAV")
            return
        }
        guard settings.validationError == nil,
              let password = keychain.password(url: settings.normalizedURL, username: settings.username) else {
            status = .failed("同步设置不完整")
            return
        }
        let configuration = WebDavTransportConfiguration(
            baseUrl: settings.normalizedURL,
            credentials: WebDavCredentials(username: settings.username, password: password),
            requestTimeoutMillis: 15_000
        )
        database.configureAutomaticWebDavSync(configuration: configuration, onComplete: completionHandler())
        configured = true
        status = .idle
        database.setSyncNetworkAvailable(available: monitor?.currentPath.status != .unsatisfied)
        database.setSyncForeground(active: true)
    }

    private func disable() {
        if configured { database.disableAutomaticSync() }
        configured = false
        status = .disabled
    }

    private func completionHandler() -> (WebDavChangeLogSyncOutcome) -> Void {
        { @Sendable [weak self] outcome in
            let converted = Outcome(outcome)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.record(converted) } }
        }
    }

    private func record(_ outcome: Outcome) {
        let transient = !outcome.succeeded && Self.isTransient(outcome.failure ?? "")
        transientFailures = transient ? transientFailures + 1 : 0
        // 第一次临时错误（刚唤醒、网络切换）不当作失败显示，稍后自动重试。
        let quiet = transient && transientFailures == 1
        let message = quiet ? Self.transientMessage : outcome.failure.map(Self.friendly)
        let entry = LogEntry(date: Date(), succeeded: outcome.succeeded, applied: outcome.applied, message: message)
        log.insert(entry, at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }
        if outcome.succeeded {
            status = .succeeded(entry.date)
            Diagnostics.sync.info("sync succeeded applied=\(outcome.applied, privacy: .public)")
        } else if quiet {
            if case .syncing = status { status = .idle }
            Diagnostics.sync.notice("sync transient failure, retrying: \(outcome.failure ?? "", privacy: .private)")
            if !appActive { scheduleTransientRetry() }
        } else {
            status = .failed(entry.message ?? "同步失败")
            Diagnostics.sync.error("sync failed transient=\(transient, privacy: .public): \(outcome.failure ?? "", privacy: .private)")
        }
        if outcome.applied > 0 { didApplyRemoteChanges() }
    }

    private var inWakeGrace: Bool { wakeGraceUntil.map { Date() < $0 } ?? false }

    private func startBackgroundSync() {
        _ = database.startSync(trigger: SyncTrigger.periodic, onComplete: completionHandler())
    }

    private func scheduleTransientRetry() {
        retryTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.configured, !self.appActive, !self.inWakeGrace else { return }
            self.startBackgroundSync()
        }
        retryTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transientRetrySeconds, execute: task)
    }

    /// 睡眠前把网络标为不可用；唤醒后等一会儿再恢复，避免在网络就绪前同步失败。
    private func observeSleep() {
        guard sleepObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        sleepObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
    }

    func willSleep() {
        wakeTask?.cancel()
        retryTask?.cancel()
        if configured { database.setSyncNetworkAvailable(available: false) }
    }

    func didWake(grace: TimeInterval = SyncController.wakeGraceSeconds) {
        wakeGraceUntil = Date().addingTimeInterval(grace)
        wakeTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.wakeGraceUntil = nil
            guard self.configured else { return }
            // 恢复网络状态：前台时 Core 会立即同步一次；后台时补上等待期内跳过的那次。
            self.database.setSyncNetworkAvailable(available: self.monitor?.currentPath.status != .unsatisfied)
            if !self.appActive { self.startBackgroundSync() }
        }
        wakeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: task)
    }

    static let transientMessage = "暂时连不上服务器（可能刚唤醒或网络切换），稍后自动重试"

    /// 找不到服务器、超时、断网、连接中断等临时错误（NSURLError -1001/-1003/-1004/-1005/-1009 等）。
    static func isTransient(_ message: String) -> Bool {
        let codes = ["-1001", "-1003", "-1004", "-1005", "-1009", "-1020"]
        if codes.contains(where: { message.contains("Code=\($0)") || message.contains("code: \($0)") || message.contains("(\($0))") }) { return true }
        let phrases = ["timed out", "timeout", "could not be found", "unresolvedaddress", "nodename nor servname",
                       "network connection was lost", "appears to be offline", "network is unavailable", "no such record"]
        let lower = message.lowercased()
        return phrases.contains { lower.contains($0) }
    }

    private func startNetworkMonitor() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.configured, !self.inWakeGrace else { return }
                    self.database.setSyncNetworkAvailable(available: available)
                }
            }
        }
        monitor.start(queue: .global(qos: .utility))
        self.monitor = monitor
    }

    /// 把常见的传输错误转成中文说明；不包含密码。
    static func friendly(_ message: String) -> String {
        if message.contains("HTTP 401") || message.contains("HTTP 403") { return "用户名或应用密码不正确（\(message)）" }
        if message.contains("HTTP 404") { return "服务器上找不到同步目录（\(message)）" }
        if message.contains("conditional write") { return "云端数据刚被其他设备更新，稍后会自动重试" }
        if message.localizedCaseInsensitiveContains("timeout") || message.localizedCaseInsensitiveContains("timed out") { return "连接超时，请检查网络" }
        if isTransient(message) { return "连不上服务器，请检查网络或 VPN（\(message)）" }
        return message
    }
}

enum SyncError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
