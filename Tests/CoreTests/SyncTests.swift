import XCTest
import Shared
@testable import Deadliner_for_macOS

/// 内存中的「云端」，实现 Core 的 SyncBlobTransport；用于在测试中模拟两台设备经同一份同步文件互通。
final class InMemoryBlobTransport: NSObject, SyncBlobTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: (data: Data, version: Int)] = [:]
    private var collections: Set<String> = []
    private var counter = 0

    func data(at path: String) -> Data? { lock.withLock { files[path]?.data } }

    func close() {}

    func read(path: String, completionHandler: @escaping (SyncBlob?, (any Error)?) -> Void) {
        let file = lock.withLock { files[path] }
        completionHandler(file.map { SyncBlob(bytes: Self.kotlinBytes($0.data), version: "v\($0.version)") }, nil)
    }

    func write(path: String, bytes: KotlinByteArray, condition: any SyncWriteCondition, completionHandler: @escaping ((any Error)?) -> Void) {
        let data = Self.data(bytes)
        let rejected: Bool = lock.withLock {
            let current = files[path]
            if condition is SyncWriteConditionCreateOnly, current != nil { return true }
            if let match = condition as? SyncWriteConditionMatchVersion, "v\(current?.version ?? -1)" != match.value { return true }
            counter += 1
            files[path] = (data, counter)
            return false
        }
        completionHandler(rejected ? NSError(domain: "InMemoryBlobTransport", code: 412) : nil)
    }

    func ensureCollection(path: String, completionHandler: @escaping (KotlinBoolean?, (any Error)?) -> Void) {
        // 返回值表示「目录可用」（已存在或刚创建）。
        lock.withLock { _ = collections.insert(path) }
        completionHandler(KotlinBoolean(bool: true), nil)
    }

    static func kotlinBytes(_ data: Data) -> KotlinByteArray {
        let array = KotlinByteArray(size: Int32(data.count))
        for (index, byte) in data.enumerated() { array.set(index: Int32(index), value: Int8(bitPattern: byte)) }
        return array
    }

    static func data(_ bytes: KotlinByteArray) -> Data {
        Data((0..<bytes.size).map { UInt8(bitPattern: bytes.get(index: $0)) })
    }
}

/// 第六步验收：两台设备经 Core 的同步引擎互通（新建、修改、删除都能传过去），同步文件格式与手机一致。
@MainActor
final class SyncTests: XCTestCase {
    private var directory: URL!
    private var deviceA: MacCoreContainer!
    private var deviceB: MacCoreContainer!
    private var syncA: SyncController!
    private var syncB: SyncController!
    private let cloud = InMemoryBlobTransport()
    private var defaults: UserDefaults!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        deviceA = MacCoreContainer(databaseURL: directory.appendingPathComponent("a.db"), deviceId: "device-a")
        deviceB = MacCoreContainer(databaseURL: directory.appendingPathComponent("b.db"), deviceId: "device-b")
        defaults = UserDefaults(suiteName: "deadliner-sync-tests-\(UUID().uuidString)")
        syncA = SyncController(database: deviceA.database, defaults: defaults) {}
        syncB = SyncController(database: deviceB.database, defaults: defaults) {}
        syncA.configureForTesting(transport: cloud)
        syncB.configureForTesting(transport: cloud)
    }

    override func tearDown() async throws {
        syncA?.stop()
        syncB?.stop()
        deviceA?.close()
        deviceB?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testTwoDevicesExchangeCreateEditAndDelete() async throws {
        let commandsA = TaskCommands(database: deviceA.database) {}
        let commandsB = TaskCommands(database: deviceB.database) {}
        let uid = try commandsA.save(TaskDraft(title: "从 A 新建", subtasks: [.init(id: "sub-1", content: "子任务", isCompleted: false)]))

        try await sync(syncA)
        try await sync(syncB)
        let received = try XCTUnwrap(deviceB.database.tasks.find(uid: uid), "B 应收到 A 新建的任务")
        XCTAssertEqual(received.title, "从 A 新建")
        XCTAssertEqual(received.subtasks.filter { !$0.isDeleted }.map(\.content), ["子任务"])

        try commandsB.toggleComplete(uid)
        try await sync(syncB)
        try await sync(syncA)
        XCTAssertEqual(deviceA.database.tasks.find(uid: uid)?.state, TaskState.completed, "A 应收到 B 的修改")

        try commandsA.delete(uid)
        try await sync(syncA)
        try await sync(syncB)
        XCTAssertTrue(deviceB.database.tasks.list().filter { $0.uid == uid && !$0.isDeleted }.isEmpty, "删除应同步到 B")
    }

    func testHabitRecordsAndCategoriesSync() async throws {
        let categoryUid = try CategoryCommands(database: deviceA.database) {}.create(name: "同步分类", iconKey: "flag", colorHex: "#EF4444")
        var draft = HabitDraft()
        draft.name = "同步习惯"
        draft.categoryId = categoryUid
        let habitUid = try HabitCommands(database: deviceA.database) {}.save(draft)
        let today = HabitDates.string(Date())
        _ = deviceA.database.habits.applyPrimaryRecordAction(habitUid: habitUid, occurredOn: today, occurredAt: CoreClock.now())

        try await sync(syncA)
        try await sync(syncB)
        XCTAssertEqual(deviceB.database.categories.find(uid: categoryUid)?.name, "同步分类")
        XCTAssertEqual(deviceB.database.habits.find(uid: habitUid)?.categoryUid, categoryUid)
        XCTAssertFalse(deviceB.database.habits.records(habitUid: habitUid).isEmpty, "打卡记录应同步到 B")
    }

    func testRemoteFileUsesPhoneFormat() async throws {
        _ = try TaskCommands(database: deviceA.database) {}.save(TaskDraft(title: "格式"))
        try await sync(syncA)
        let data = try XCTUnwrap(cloud.data(at: "Deadliner/kmp-changelog-v1.json"), "同步文件路径应与手机相同")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["formatVersion"] as? Int, 6)
        let snapshot = try XCTUnwrap(json["snapshot"] as? [String: Any])
        XCTAssertEqual(snapshot["format_version"] as? Int, 6)
        // 手机 6.0.0-Beta 的严格解析会拒绝未知字段；以下字段表取自手机 APK（protocol-reference）。
        XCTAssertTrue(Set(json.keys).isSubset(of: ["formatVersion", "snapshot", "changes"]), "\(json.keys)")
        let phoneSnapshotKeys: Set<String> = ["format_version", "version", "categories", "tasks", "focus_sessions", "habits",
                                              "captures", "memory_fragments", "memory_user_profile", "user_profiles"]
        XCTAssertTrue(Set(snapshot.keys).isSubset(of: phoneSnapshotKeys), "\(snapshot.keys)")
        let tasks = try XCTUnwrap(snapshot["tasks"] as? [[String: Any]])
        XCTAssertTrue(tasks.contains { ($0["doc"] as? [String: Any])?["title"] as? String == "格式" })
        XCTAssertEqual(syncA.log.first?.succeeded, true)
    }

    // MARK: - Helpers

    private func sync(_ controller: SyncController) async throws {
        let before = controller.log.count
        controller.syncNow()
        let deadline = Date().addingTimeInterval(10)
        while controller.log.count == before {
            if Date() > deadline { return XCTFail("同步超时") }
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        // 自动同步可能与手动同步合并；等调度稳定后再检查结果。
        try await _Concurrency.Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(controller.log.first?.succeeded, true, controller.log.first?.message ?? "")
    }
}

/// 设置校验、钥匙串与「检测服务器」。
@MainActor
final class SyncSettingsTests: XCTestCase {
    func testValidation() {
        XCTAssertEqual(SyncSettings(serverURL: "", username: "a", enabled: true).validationError, "请填写服务器地址")
        XCTAssertEqual(SyncSettings(serverURL: "dav.example.com", username: "a", enabled: true).validationError, "服务器地址需要以 https:// 开头")
        XCTAssertEqual(SyncSettings(serverURL: "https://dav.example.com/dav", username: " ", enabled: true).validationError, "请填写用户名")
        XCTAssertNil(SyncSettings(serverURL: "https://dav.example.com/dav", username: "me", enabled: true).validationError)
        XCTAssertEqual(SyncSettings(serverURL: " https://dav.example.com/dav ", username: "me", enabled: true).normalizedURL, "https://dav.example.com/dav/")
    }

    func testKeychainRoundTrip() {
        let store = KeychainPasswordStore(service: "com.deadliner.macos.tests.\(UUID().uuidString)")
        defer { store.deletePassword(url: "https://example.test/", username: "me") }
        XCTAssertNil(store.password(url: "https://example.test/", username: "me"))
        XCTAssertTrue(store.setPassword("test-only-1", url: "https://example.test/", username: "me"))
        XCTAssertTrue(store.setPassword("test-only-2", url: "https://example.test/", username: "me"))
        XCTAssertEqual(store.password(url: "https://example.test/", username: "me"), "test-only-2")
    }

    func testInvalidSettingsAreRejectedBeforeReachingCore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-sync-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = MacCoreContainer(databaseURL: directory.appendingPathComponent("db"), deviceId: "t")
        defer { container.close() }
        let defaults = UserDefaults(suiteName: "deadliner-sync-settings-\(UUID().uuidString)")!
        let keychain = KeychainPasswordStore(service: "com.deadliner.macos.tests.\(UUID().uuidString)")
        let controller = SyncController(database: container.database, keychain: keychain, defaults: defaults) {}
        XCTAssertThrowsError(try controller.save(SyncSettings(serverURL: "ftp://x", username: "me", enabled: true), password: "p"))
        XCTAssertThrowsError(try controller.save(SyncSettings(serverURL: "https://example.test/", username: "me", enabled: true), password: nil))
        XCTAssertEqual(controller.status, .disabled)
    }

    func testEnablingSyncBacksUpCloudFileFirst() async throws {
        MockDavServer.reset(ignoresIfNoneMatch: true, etagOnHead: false)
        MockDavServer.seed(path: "/dav/Deadliner/kmp-changelog-v1.json", data: Data("{\"formatVersion\":6}".utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDavServer.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = MacCoreContainer(databaseURL: directory.appendingPathComponent("db"), deviceId: "t")
        defer { container.close() }
        let keychain = KeychainPasswordStore(service: "com.deadliner.macos.tests.\(UUID().uuidString)")
        defer { keychain.deletePassword(url: "https://dav.example.test/dav/", username: "me") }
        let controller = SyncController(
            database: container.database, keychain: keychain,
            defaults: UserDefaults(suiteName: "deadliner-backup-\(UUID().uuidString)")!,
            backupSession: URLSession(configuration: configuration),
            backupDirectory: { directory.appendingPathComponent("backups") }
        ) {}
        defer { controller.stop() }
        try controller.save(SyncSettings(serverURL: "https://dav.example.test/dav/", username: "me", enabled: true), password: "test-only")
        let deadline = Date().addingTimeInterval(5)
        while controller.lastBackup == nil && Date() < deadline { try await _Concurrency.Task.sleep(nanoseconds: 20_000_000) }
        let backup = try XCTUnwrap(controller.lastBackup, "启用同步前应先备份云端文件")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{\"formatVersion\":6}")
    }

    func testProbeAgainstNutstoreLikeServer() async {
        MockDavServer.reset(ignoresIfNoneMatch: true, etagOnHead: false)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDavServer.self]
        let probe = WebDavProbe(
            settings: SyncSettings(serverURL: "https://dav.example.test/dav/", username: "me", enabled: true),
            password: "test-only", session: URLSession(configuration: configuration)
        )
        let checks = await probe.run()
        let states = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0.state) })
        let details = checks.map { "\($0.id): \($0.detail)" }.joined(separator: "; ")
        XCTAssertEqual(states["auth"], .ok, details)
        XCTAssertEqual(states["dir"], .ok)
        XCTAssertEqual(states["write"], .ok)
        XCTAssertEqual(states["createOnly"], .warning)
        XCTAssertEqual(states["etag"], .ok)
        XCTAssertEqual(states["ifMatch"], .ok)
        XCTAssertEqual(states["matchWrite"], .ok)
        XCTAssertFalse(MockDavServer.touchedSyncFile, "检测不应读写同步文件")
    }

    func testProbeReportsWrongPassword() async {
        MockDavServer.reset(ignoresIfNoneMatch: false, etagOnHead: true, rejectAuth: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDavServer.self]
        let checks = await WebDavProbe(
            settings: SyncSettings(serverURL: "https://dav.example.test/dav/", username: "me", enabled: true),
            password: "wrong", session: URLSession(configuration: configuration)
        ).run()
        XCTAssertEqual(checks.last?.id, "auth")
        XCTAssertEqual(checks.last?.state, .failed)
    }
}

/// 模拟 WebDAV 服务器（URLProtocol），可以模仿坚果云：HEAD 不返回 ETag、忽略 If-None-Match。
final class MockDavServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var files: [String: (Data, Int)] = [:]
    nonisolated(unsafe) private static var directories: Set<String> = ["/dav"]
    nonisolated(unsafe) private static var ignoresIfNoneMatch = false
    nonisolated(unsafe) private static var etagOnHead = true
    nonisolated(unsafe) private static var rejectAuth = false
    nonisolated(unsafe) private static var version = 0
    nonisolated(unsafe) static var touchedSyncFile = false

    static func seed(path: String, data: Data) {
        version += 1
        files[path] = (data, version)
    }

    static func reset(ignoresIfNoneMatch: Bool, etagOnHead: Bool, rejectAuth: Bool = false) {
        files = [:]
        directories = ["/dav"]
        self.ignoresIfNoneMatch = ignoresIfNoneMatch
        self.etagOnHead = etagOnHead
        self.rejectAuth = rejectAuth
        version = 0
        touchedSyncFile = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var path = request.url!.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if path.contains("kmp-changelog") { Self.touchedSyncFile = true }
        let (status, headers) = handle(method: request.httpMethod ?? "GET", path: path, body: bodyData())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = (request.httpMethod ?? "GET") == "GET" && (200..<300).contains(status) ? Self.files[path]?.0 ?? Data() : Data()
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func bodyData() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private func handle(method: String, path: String, body: Data?) -> (Int, [String: String]) {
        if Self.rejectAuth { return (401, [:]) }
        switch method {
        case "PROPFIND":
            return Self.directories.contains(path) || Self.files[path] != nil ? (207, [:]) : (404, [:])
        case "MKCOL":
            Self.directories.insert(path)
            return (201, [:])
        case "PUT":
            let current = Self.files[path]
            if request.value(forHTTPHeaderField: "If-None-Match") == "*", current != nil, !Self.ignoresIfNoneMatch { return (412, [:]) }
            if let match = request.value(forHTTPHeaderField: "If-Match"), match != "\"v\(current?.1 ?? -1)\"" { return (412, [:]) }
            Self.version += 1
            Self.files[path] = (body ?? Data(), Self.version)
            return (current == nil ? 201 : 204, [:])
        case "GET":
            guard let file = Self.files[path] else { return (404, [:]) }
            return (200, ["ETag": "\"v\(file.1)\""])
        case "HEAD":
            guard let file = Self.files[path] else { return (404, [:]) }
            return (200, Self.etagOnHead ? ["ETag": "\"v\(file.1)\""] : [:])
        case "DELETE":
            Self.files[path] = nil
            return (204, [:])
        default:
            return (405, [:])
        }
    }
}
