import Foundation
import Shared

/// 本机备份文件：内容由 Core 的 `BackupService.export()` 生成（完整快照，与其他客户端同一格式）。
struct LocalBackup {
    let database: DeadlinerDatabase

    /// 默认文件名，例如 `Deadliner-备份-20261101-1530.json`。
    static func suggestedFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "Deadliner-备份-\(formatter.string(from: now)).json"
    }

    func export(to url: URL) throws {
        try Data(database.backups.export().utf8).write(to: url, options: .atomic)
    }
}
