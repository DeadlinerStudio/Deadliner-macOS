import Foundation

/// 启用同步前，把云端同步文件原样下载一份保存在本机，便于出问题时恢复。
/// 只读取，不修改云端。云端还没有同步文件（HTTP 404）时视为无需备份。
struct RemoteBackup {
    enum Result: Equatable {
        case saved(URL)
        case nothingToBackUp
    }

    let settings: SyncSettings
    let password: String
    var session: URLSession = .shared
    var directory: URL

    static let remotePath = "Deadliner/kmp-changelog-v1.json"

    static func defaultDirectory() throws -> URL {
        let directory = try AppPaths.applicationSupportDirectory().appendingPathComponent("cloud-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func run() async throws -> Result {
        guard let url = URL(string: settings.normalizedURL + Self.remotePath) else { throw SyncError.invalid("服务器地址格式不正确") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Basic \(Data("\(settings.username):\(password)".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.invalid("备份云端数据失败：服务器没有响应") }
        switch http.statusCode {
        case 200:
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = directory.appendingPathComponent("kmp-changelog-v1-\(stamp).json")
            try data.write(to: file, options: .atomic)
            return .saved(file)
        case 404:
            return .nothingToBackUp
        case 401, 403:
            throw SyncError.invalid("备份云端数据失败：用户名或应用密码不正确")
        default:
            throw SyncError.invalid("备份云端数据失败：HTTP \(http.statusCode)")
        }
    }
}
