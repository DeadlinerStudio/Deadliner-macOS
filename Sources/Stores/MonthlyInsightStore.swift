import Foundation
import Observation
import Shared

struct MonthlyInsight: Codable, Equatable {
    let month: String
    let summary: String
    let keywords: [String]
}

/// App-lifetime ownership prevents tab/window disappearance from cancelling analysis.
@MainActor
@Observable
final class MonthlyInsightStore {
    static let shared = MonthlyInsightStore()
    private(set) var result: MonthlyInsight?
    private(set) var loading = false
    private(set) var error: String?
    @ObservationIgnored private var activeMonth: String?
    @ObservationIgnored private var pending: [String: AppleMonthlyInsightBridge] = [:]
    @ObservationIgnored private let directory: URL?
    private struct Record: Codable { var attempted: Bool; var result: MonthlyInsight? }

    init(directory: URL? = nil) {
        self.directory = directory ?? (try? AppPaths.applicationSupportDirectory().appendingPathComponent("MonthlyReviews"))
    }

    func resolve(review: OverviewStore.MonthReview, retry: Bool = false) {
        guard let month = review.monthStart, month < OverviewPeriod.key(OverviewPeriod.month()) else { return }
        activeMonth = month
        result = nil
        error = nil
        loading = pending[month] != nil
        guard let directory else { error = "无法打开复盘存储目录"; return }
        let url = directory.appendingPathComponent(month + ".json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
                if let result = record.result, result.month == month, !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.result = result; loading = false; return
                }
                if record.attempted && !retry && pending[month] == nil { error = "上次分析未完成，请点击重试"; return }
            }
            if pending[month] != nil { return }
            guard LifiAvailability.shared.isAvailable else { error = "当前构建未包含 AI 服务"; return }
            guard let config = MonthlyInsightSettings.configuration() else { error = "配置 AI 服务后可生成月度洞察"; return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Record(attempted: true)).write(to: url, options: .atomic)
            let bridge = AppleMonthlyInsightBridge()
            pending[month] = bridge
            loading = true
            let metrics = "任务总数：\(review.totalTasks)\n已完成：\(review.completedTasks)\n完成率：\(review.completionRate)%\n逾期（含放弃）：\(review.overdueTasks)\n平均完成用时：\(review.averageCompletionMinutes.map { "\($0) 分钟" } ?? "无数据")"
            bridge.generate(config: config, month: String(month.prefix(7)), metrics: metrics, titles: review.completedTitles, onSuccess: { [self] summary, keywords in
                MainActor.assumeIsolated {
                    let value = MonthlyInsight(month: month, summary: summary, keywords: keywords)
                    do {
                        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.coderInvalidValue) }
                        try JSONEncoder().encode(Record(attempted: true, result: value)).write(to: url, options: .atomic)
                        if activeMonth == month { result = value; error = nil }
                    } catch { if activeMonth == month { self.error = "无法保存月度洞察，请重试" } }
                    pending[month] = nil
                    if activeMonth == month { loading = false }
                }
            }, onError: { [self] message in
                MainActor.assumeIsolated {
                    pending[month] = nil
                    if activeMonth == month { error = message; loading = false }
                }
            })
        } catch { self.error = "复盘存储读写失败，请重试"; loading = false }
    }
}

@MainActor
enum MonthlyInsightSettings {
    static let keychain = KeychainPasswordStore(service: "com.deadliner.macos.monthly-ai")
    static func configuration() -> AIConfig? {
        let defaults = UserDefaults.standard
        let url = defaults.string(forKey: "overview.ai.url") ?? ""
        let model = defaults.string(forKey: "overview.ai.model") ?? ""
        guard defaults.bool(forKey: "overview.ai.enabled"),
              let parsed = URL(string: url), parsed.scheme == "https", parsed.host != nil,
              !model.trimmingCharacters(in: .whitespaces).isEmpty,
              let key = keychain.password(url: url, username: "api"), !key.isEmpty else { return nil }
        return AIConfig(apiKey: key, baseUrl: url, model: model, platform: "macos", timezone: TimeZone.current.identifier,
                        temperature: nil, nativeToolCalling: false, preferredLanguage: "zh-CN")
    }
}
