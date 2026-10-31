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

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private let keychain: KeychainPasswordStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let didApplyRemoteChanges: () -> Void
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var configured = false

    init(database: DeadlinerDatabase, keychain: KeychainPasswordStore = .init(), defaults: UserDefaults = .standard,
         didApplyRemoteChanges: @escaping () -> Void) {
        self.database = database
        self.keychain = keychain
        self.defaults = defaults
        self.didApplyRemoteChanges = didApplyRemoteChanges
        settings = SyncSettings.load(from: defaults)
    }

    var hasPassword: Bool {
        keychain.password(url: settings.normalizedURL, username: settings.username) != nil
    }

    /// 启动时调用：已启用同步时按保存的设置开始自动同步。
    func start() {
        startNetworkMonitor()
        if settings.enabled { applyConfiguration() }
    }

    /// 保存设置。`password` 为 nil 表示保留钥匙串中已有的密码。
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
            guard hasPassword else { throw SyncError.invalid("请填写应用密码") }
            applyConfiguration()
        } else {
            disable()
        }
    }

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
        guard configured else { return }
        database.setSyncForeground(active: active)
    }

    func stop() {
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
        let entry = LogEntry(date: Date(), succeeded: outcome.succeeded, applied: outcome.applied,
                             message: outcome.failure.map(Self.friendly))
        log.insert(entry, at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }
        status = outcome.succeeded ? .succeeded(entry.date) : .failed(entry.message ?? "同步失败")
        if outcome.applied > 0 { didApplyRemoteChanges() }
    }

    private func startNetworkMonitor() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.configured else { return }
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
        return message
    }
}

enum SyncError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
