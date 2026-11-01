import Foundation
import Shared

/// 本机备份文件：内容由 Core 的 `BackupService.export()` 生成（完整快照，与其他客户端同一格式），
/// 导入由 `BackupService.restore()` 完成（整库替换）。
struct LocalBackup {
    enum ImportError: LocalizedError, Equatable {
        case notBackup
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .notBackup: "这不是 Deadliner 的备份文件。"
            case .rejected(let detail): "备份文件无法导入：\(detail)"
            }
        }
    }

    let database: DeadlinerDatabase

    /// 默认文件名，例如 `Deadliner-备份-20261101-1530.json`。
    static func suggestedFileName(prefix: String = "Deadliner-备份", now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "\(prefix)-\(formatter.string(from: now)).json"
    }

    /// 导入前自动保存当前数据的位置。
    static func defaultSafetyDirectory() throws -> URL {
        let directory = try AppPaths.applicationSupportDirectory().appendingPathComponent("local-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func export(to url: URL) throws {
        try Data(database.backups.export().utf8).write(to: url, options: .atomic)
    }

    /// 粗略确认是 Deadliner 备份（顶层含 `snapshot` 对象），用于在确认框之前挡住选错的文件。
    /// 完整校验由 Core 在导入时完成。
    static func check(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["snapshot"] is [String: Any],
              let raw = String(data: data, encoding: .utf8) else { throw ImportError.notBackup }
        return raw
    }

    /// 先把当前数据导出到 `safetyDirectory`，再用备份替换本机数据。返回自动备份的位置。
    /// Core 拒绝文件时本机数据不变（替换在一个事务中完成）。
    @discardableResult
    func restore(_ raw: String, safetyDirectory: URL) throws -> URL {
        let safety = safetyDirectory.appendingPathComponent(Self.suggestedFileName(prefix: "导入前自动备份"))
        try export(to: safety)
        do {
            try database.backups.restore(raw: raw)
        } catch {
            // Core 的说明是英文（例如 "Unsupported backup format"），原样附在后面便于排查。
            throw ImportError.rejected(error.localizedDescription)
        }
        return safety
    }
}
