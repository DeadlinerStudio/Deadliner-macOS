import Foundation
import OSLog
import Shared

/// 诊断日志。
/// - Core 的记录写入 `Application Support/com.deadliner.macos/Diagnostics/`（与安卓相同的 JSONL 与文本文件）；
/// - Mac 端自己的关键动作（同步结果、通知重排）写入系统日志，子系统 `com.deadliner.macos`。
/// 只记录数量、状态和错误信息；任务标题、备注和凭据都不写入（错误信息可能含服务器地址）。
enum Diagnostics {
    static let subsystem = "com.deadliner.macos"
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// 单个日志文件的上限；超过后改名为 `.1`（只保留一份旧文件）。
    static let maxFileBytes = 2 * 1024 * 1024
    static let fileNames = ["deadliner-diagnostics.jsonl", "deadliner-diagnostics.log"]
    nonisolated(unsafe) private static var rotationTimer: Timer?

    /// 启动时调用一次（在打开数据库之前），之后 Core 的日志都写入诊断目录。
    static func configureCoreLog(root: URL, fileManager: FileManager = .default) {
        let directory = root.appendingPathComponent("Diagnostics", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        rotate(in: directory, fileManager: fileManager)
        // 应用常常连续运行好几天：每小时检查一次大小（Core 每条记录都重新打开文件，改名后自动写入新文件）。
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in rotate(in: directory) }
        PlatformLogSink.shared.configure(directory: root.path, processId: KotlinLong(value: Int64(ProcessInfo.processInfo.processIdentifier)))
    }

    /// 诊断目录（设置中「在访达中显示」使用）。
    static func directory() -> URL? {
        try? AppPaths.applicationSupportDirectory().appendingPathComponent("Diagnostics", isDirectory: true)
    }

    static func rotate(in directory: URL, fileManager: FileManager = .default) {
        for name in fileNames {
            let file = directory.appendingPathComponent(name)
            guard let size = (try? fileManager.attributesOfItem(atPath: file.path))?[.size] as? Int, size > maxFileBytes else { continue }
            let old = directory.appendingPathComponent(name + ".1")
            try? fileManager.removeItem(at: old)
            try? fileManager.moveItem(at: file, to: old)
        }
    }
}
