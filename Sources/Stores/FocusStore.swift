import Foundation
import Observation
import Shared

/// 专注记录（只读）：汇总来自 Core `LocalFocusStatisticsRepository.overview()`，
/// 列表来自 `FocusSessionRepository.recent`。Mac 端不新建、不编辑专注记录。
@MainActor
@Observable
final class FocusStore {
    struct Summary: Equatable {
        var totalSeconds: Int
        var sessionCount: Int

        init(totalSeconds: Int, sessionCount: Int) {
            self.totalSeconds = totalSeconds
            self.sessionCount = sessionCount
        }

        init(core summary: FocusStatisticsSummary) {
            self.init(totalSeconds: Int(summary.totalDurationSeconds), sessionCount: Int(summary.sessionCount))
        }
    }

    struct Session: Identifiable, Equatable {
        let id: String
        var title: String
        var isHabit: Bool
        var isCountdown: Bool
        var startedAt: Date?
        var endedAt: Date?
        var durationSeconds: Int
        var completionKind: String
    }

    private(set) var today = Summary(totalSeconds: 0, sessionCount: 0)
    private(set) var thisWeek = Summary(totalSeconds: 0, sessionCount: 0)
    private(set) var thisMonth = Summary(totalSeconds: 0, sessionCount: 0)
    private(set) var allTime = Summary(totalSeconds: 0, sessionCount: 0)
    private(set) var sessions: [Session] = []
    /// 最近 7 天每天的专注时长（Core overview.daily）。
    private(set) var recentDays: [DayPoint] = []

    struct DayPoint: Identifiable, Equatable {
        let date: String
        let seconds: Int
        var id: String { date }
    }

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private var bridge: IosOverviewStateBridge?

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    /// 调整一条专注记录的时长（Core 只允许改短）。`completion` 在主线程回调，失败时带说明。
    func adjust(_ id: String, seconds: Int, completion: @escaping (String?) -> Void) {
        mutate(id, seconds: KotlinLong(value: Int64(seconds)), completion: completion)
    }

    /// 删除一条专注记录（软删除，会同步到其他设备）。
    func delete(_ id: String, completion: @escaping (String?) -> Void) {
        mutate(id, seconds: nil, completion: completion)
    }

    private func mutate(_ id: String, seconds: KotlinLong?, completion: @escaping (String?) -> Void) {
        if bridge == nil { bridge = IosOverviewStateBridge(database: database) }
        bridge?.mutateFocusSession(sessionUid: id, durationSeconds: seconds) { [weak self] outcome, error in
            MainActor.assumeIsolated {
                self?.refresh()
                switch outcome.name {
                case "APPLIED", "NO_OP": completion(nil)
                case "INVALID_DURATION": completion("时长只能改短，且不能为 0")
                default: completion(error ?? "操作失败（\(outcome.name)）")
                }
            }
        }
    }

    func refresh() {
        let overview = database.focusStatistics.overview()
        today = Summary(core: overview.today)
        thisWeek = Summary(core: overview.thisWeek)
        thisMonth = Summary(core: overview.thisMonth.summary)
        allTime = Summary(core: overview.allTime)
        recentDays = overview.daily.suffix(7).map { DayPoint(date: $0.startDate, seconds: Int($0.durationSeconds)) }
        sessions = database.focusSessions.recent(limit: 300)
            .filter { !$0.isDeleted }
            .map {
                Session(
                    id: $0.uid,
                    title: $0.targetTitleSnapshot,
                    isHabit: $0.boundTarget.kind.name == "HABIT",
                    isCountdown: $0.mode.name == "COUNTDOWN",
                    startedAt: CoreDates.parseInstant($0.startedAt),
                    endedAt: CoreDates.parseInstant($0.endedAt),
                    durationSeconds: Int($0.durationSeconds),
                    completionKind: $0.completionKind.name
                )
            }
    }
}
