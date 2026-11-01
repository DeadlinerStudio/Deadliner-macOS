import XCTest
import Shared
@testable import DeadlinerTestHost

/// 第二期：备份的导出与导入经过 Core 的 BackupService；无效文件给出错误而不是让应用退出。
@MainActor
final class BackupTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var backup: LocalBackup { LocalBackup(database: container.database) }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-backup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(
            databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
            deviceId: "macos-test-device"
        )
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func addTask(_ title: String) throws -> String {
        var draft = TaskDraft()
        draft.title = title
        return try TaskCommands(database: container.database) {}.save(draft)
    }

    private var taskTitles: Set<String> {
        Set(container.database.tasks.list().filter { !$0.isDeleted }.map(\.title))
    }

    func testExportWritesCoreSnapshot() throws {
        _ = try addTask("示例导出")
        let url = directory.appendingPathComponent(LocalBackup.suggestedFileName())
        try backup.export(to: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(root["formatVersion"] as? Int, 1)
        let snapshot = try XCTUnwrap(root["snapshot"] as? [String: Any])
        XCTAssertEqual((snapshot["tasks"] as? [Any])?.count, 1)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Deadliner-备份-"))
    }

    func testImportReplacesDataAndKeepsSafetyCopy() throws {
        _ = try addTask("示例甲")
        let url = directory.appendingPathComponent("backup.json")
        try backup.export(to: url)
        _ = try addTask("示例乙")
        XCTAssertEqual(taskTitles, ["示例甲", "示例乙"])

        let raw = try LocalBackup.check(Data(contentsOf: url))
        let safetyDirectory = directory.appendingPathComponent("safety", isDirectory: true)
        try FileManager.default.createDirectory(at: safetyDirectory, withIntermediateDirectories: true)
        let safety = try backup.restore(raw, safetyDirectory: safetyDirectory)

        XCTAssertEqual(taskTitles, ["示例甲"])
        // 自动备份包含导入前的两个任务。
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: safety)) as? [String: Any])
        XCTAssertEqual(((saved["snapshot"] as? [String: Any])?["tasks"] as? [Any])?.count, 2)
    }

    func testWrongFilesAreRejectedWithoutChangingData() throws {
        _ = try addTask("示例保留")
        XCTAssertThrowsError(try LocalBackup.check(Data("not json".utf8))) { XCTAssertEqual($0 as? LocalBackup.ImportError, .notBackup) }
        XCTAssertThrowsError(try LocalBackup.check(Data(#"{"tasks": []}"#.utf8))) { XCTAssertEqual($0 as? LocalBackup.ImportError, .notBackup) }

        // 形状像备份但内容不对：由 Core 拒绝，抛出错误（以前会让应用直接退出）。
        let bogus = [
            #"{"formatVersion": 99, "snapshot": {}}"#,
            #"{"formatVersion": 1, "snapshot": {"formatVersion": 6, "unexpected": true}}"#,
            #"{"formatVersion": 1, "snapshot": {"formatVersion": 2}}"#,
        ]
        for raw in bogus {
            let checked = try LocalBackup.check(Data(raw.utf8))
            XCTAssertThrowsError(try backup.restore(checked, safetyDirectory: directory)) { error in
                guard case .rejected = error as? LocalBackup.ImportError else { return XCTFail("\(error)") }
            }
        }
        XCTAssertEqual(taskTitles, ["示例保留"])
    }
}
