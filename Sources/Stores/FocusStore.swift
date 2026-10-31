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

    @ObservationIgnored private let database: DeadlinerDatabase

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    func refresh() {
        let overview = database.focusStatistics.overview()
        today = Summary(core: overview.today)
        thisWeek = Summary(core: overview.thisWeek)
        thisMonth = Summary(core: overview.thisMonth.summary)
        allTime = Summary(core: overview.allTime)
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
