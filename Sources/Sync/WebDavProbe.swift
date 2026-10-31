import Foundation

/// 「检测服务器」：逐项确认 WebDAV 服务器满足 Core 同步需要的能力。
///
/// 只读写一个临时探测文件 `Deadliner/.mac-probe-<随机>.txt`，结束时删除；
/// 不会读取或改动同步文件 `Deadliner/kmp-changelog-v1.json`。
struct WebDavProbe {
    struct Check: Identifiable, Equatable {
        enum State: Equatable { case ok, warning, failed }
        let id: String
        let title: String
        let state: State
        let detail: String
    }

    let settings: SyncSettings
    let password: String
    var session: URLSession = .shared

    func run() async -> [Check] {
        var checks: [Check] = []
        let base = settings.normalizedURL
        guard let baseURL = URL(string: base) else {
            return [Check(id: "url", title: "服务器地址", state: .failed, detail: "地址格式不正确")]
        }
        checks.append(settings.usesHTTPS
            ? Check(id: "https", title: "加密连接", state: .ok, detail: "使用 HTTPS")
            : Check(id: "https", title: "加密连接", state: .warning, detail: "没有使用 HTTPS，密码和数据会以明文传输"))

        // 1. 连接与登录
        guard let root = await send("PROPFIND", baseURL, headers: ["Depth": "0"]) else {
            checks.append(Check(id: "auth", title: "连接与登录", state: .failed, detail: "无法连接服务器"))
            return checks
        }
        if root.status == 401 || root.status == 403 {
            checks.append(Check(id: "auth", title: "连接与登录", state: .failed, detail: "用户名或应用密码不正确（HTTP \(root.status)）"))
            return checks
        }
        guard (200..<300).contains(root.status) else {
            checks.append(Check(id: "auth", title: "连接与登录", state: .failed, detail: "服务器返回 HTTP \(root.status)"))
            return checks
        }
        checks.append(Check(id: "auth", title: "连接与登录", state: .ok, detail: "已登录"))

        // 2. 同步目录
        let directory = baseURL.appendingPathComponent("Deadliner", isDirectory: true)
        var dirStatus = await send("PROPFIND", directory, headers: ["Depth": "0"])?.status ?? 0
        if dirStatus == 404 {
            dirStatus = await send("MKCOL", directory)?.status ?? 0
            checks.append((200..<300).contains(dirStatus)
                ? Check(id: "dir", title: "同步目录", state: .ok, detail: "已创建 Deadliner 目录")
                : Check(id: "dir", title: "同步目录", state: .failed, detail: "无法创建 Deadliner 目录（HTTP \(dirStatus)）"))
        } else {
            checks.append((200..<300).contains(dirStatus)
                ? Check(id: "dir", title: "同步目录", state: .ok, detail: "Deadliner 目录已存在")
                : Check(id: "dir", title: "同步目录", state: .failed, detail: "无法访问 Deadliner 目录（HTTP \(dirStatus)）"))
        }
        guard checks.last?.state == .ok else { return checks }

        // 3. 写入与条件写入
        let probe = directory.appendingPathComponent(".mac-probe-\(UUID().uuidString.prefix(8)).txt")
        defer { Task { _ = await send("DELETE", probe) } }
        let created = await send("PUT", probe, body: Data("probe-1".utf8), headers: ["If-None-Match": "*"])?.status ?? 0
        guard (200..<300).contains(created) else {
            checks.append(Check(id: "write", title: "写入文件", state: .failed, detail: "无法写入（HTTP \(created)）"))
            return checks
        }
        checks.append(Check(id: "write", title: "写入文件", state: .ok, detail: "可以写入"))

        let duplicate = await send("PUT", probe, body: Data("probe-2".utf8), headers: ["If-None-Match": "*"])?.status ?? 0
        checks.append(duplicate == 412
            ? Check(id: "createOnly", title: "仅新建（If-None-Match）", state: .ok, detail: "已存在的文件不会被覆盖")
            : Check(id: "createOnly", title: "仅新建（If-None-Match）", state: .warning,
                    detail: "服务器忽略了 If-None-Match（HTTP \(duplicate)）。坚果云就是这样；只影响两台设备同时首次上传的极端情况"))

        // 4. 版本号（ETag）。部分服务器只在 GET 时返回 ETag。
        let head = await send("HEAD", probe)
        let get = await send("GET", probe)
        guard let etag = head?.etag ?? get?.etag else {
            checks.append(Check(id: "etag", title: "版本号（ETag）", state: .failed, detail: "服务器没有返回 ETag，无法安全地合并修改"))
            return checks
        }
        checks.append(Check(id: "etag", title: "版本号（ETag）", state: .ok, detail: head?.etag == nil ? "仅 GET 返回 ETag" : "支持"))

        // 5. 按版本号写入（If-Match）
        let stale = await send("PUT", probe, body: Data("probe-3".utf8), headers: ["If-Match": "\"deadliner-stale-version\""])?.status ?? 0
        checks.append(stale == 412
            ? Check(id: "ifMatch", title: "冲突检测（If-Match）", state: .ok, detail: "过期版本的写入会被拒绝")
            : Check(id: "ifMatch", title: "冲突检测（If-Match）", state: .failed,
                    detail: "过期版本的写入没有被拒绝（HTTP \(stale)），多台设备同时修改时可能丢数据"))
        let matched = await send("PUT", probe, body: Data("probe-4".utf8), headers: ["If-Match": etag])?.status ?? 0
        checks.append((200..<300).contains(matched)
            ? Check(id: "matchWrite", title: "按版本号写入", state: .ok, detail: "当前版本可以写入")
            : Check(id: "matchWrite", title: "按版本号写入", state: .failed, detail: "当前版本的写入被拒绝（HTTP \(matched)）"))
        return checks
    }

    // MARK: - HTTP

    private struct Response {
        let status: Int
        let etag: String?
    }

    private func send(_ method: String, _ url: URL, body: Data? = nil, headers: [String: String] = [:]) async -> Response? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        let token = Data("\(settings.username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return nil }
        return Response(status: http.statusCode, etag: http.value(forHTTPHeaderField: "ETag"))
    }
}
