import Foundation
import Shared

/// 一次性清理：2026-10-31 截图测试误连真实同步后写入云端的占位数据。
///
/// 只匹配标题完全等于测试占位名、且创建时间不早于开启同步时刻（2026-10-31 19:20 UTC）的条目，
/// 用 Core 的正常删除（删除记录会同步到云端与手机）。
@MainActor
struct TestDataCleanup {
    static let taskTitles: Set<String> = ["示例任务 A", "示例任务 B", "示例任务 C", "示例任务 D", "示例任务 E"]
    static let habitNames: Set<String> = ["示例习惯 A", "示例习惯 B"]
    static let cutoff = CoreDates.parseInstant("2026-10-31T19:20:00Z")!

    let database: DeadlinerDatabase

    struct Candidates: Equatable {
        var taskIds: [String]
        var habitIds: [String]
        var isEmpty: Bool { taskIds.isEmpty && habitIds.isEmpty }
    }

    func candidates() -> Candidates {
        let tasks = database.tasks.list().filter {
            !$0.isDeleted && Self.taskTitles.contains($0.title)
                && (CoreDates.parseInstant($0.createdAt).map { $0 >= Self.cutoff } ?? false)
        }
        let habits = database.habits.list().filter {
            !$0.isDeleted && Self.habitNames.contains($0.name)
                && (CoreDates.parseInstant($0.createdAt).map { $0 >= Self.cutoff } ?? false)
        }
        return Candidates(taskIds: tasks.map(\.uid), habitIds: habits.map(\.uid))
    }

    /// 删除候选条目，返回实际删除的数量。
    @discardableResult
    func run(_ candidates: Candidates) -> Int {
        let now = CoreClock.now()
        for uid in candidates.taskIds { _ = database.tasks.delete(uid: uid, updatedAt: now) }
        for uid in candidates.habitIds { database.habits.delete(uid: uid, updatedAt: now) }
        return candidates.taskIds.count + candidates.habitIds.count
    }
}
