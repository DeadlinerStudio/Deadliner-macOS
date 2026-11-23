import Foundation

/// 检查更新（与安卓「检查更新」相同的作用）：读取 GitHub 上最新发布的版本号，与本机版本比较。
/// 只读取公开的发布信息，不发送任何用户数据；不自动下载，发现新版本时由用户打开发布页下载。
enum UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/DeadlinerStudio/Deadliner-macOS/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/DeadlinerStudio/Deadliner-macOS/releases")!

    enum Outcome: Equatable {
        case upToDate(current: String)
        case available(version: String, page: URL)
    }

    struct Release: Decodable {
        let tagName: String
        let htmlURL: URL?
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url" }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 比较版本号（忽略开头的 v，按数字逐段比较，缺少的段按 0）。
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func parts(_ value: String) -> [Int] {
            value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(lhs), b = parts(rhs)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func outcome(latestTag: String, page: URL?, current: String = currentVersion) -> Outcome {
        compare(current, latestTag) == .orderedAscending
            ? .available(version: latestTag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), page: page ?? releasesPage)
            : .upToDate(current: current)
    }

    static func check(session: URLSession = .shared, current: String = currentVersion) async throws -> Outcome {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Deadliner-macOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        return outcome(latestTag: release.tagName, page: release.htmlURL, current: current)
    }
}
