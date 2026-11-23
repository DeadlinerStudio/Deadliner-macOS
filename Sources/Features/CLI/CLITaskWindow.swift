import SwiftUI

struct CLISession: Equatable {
    let endpoint: URL
    private let token: String

    init?(code: String) {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = UInt16(parts[0]), port > 0,
              parts[1].utf8.count == 64, parts[1].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let url = URL(string: "http://127.0.0.1:\(port)/v1/tasks") else { return nil }
        endpoint = url
        token = String(parts[1])
    }

    func request(revision: String?) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(revision, forHTTPHeaderField: "If-None-Match")
        return request
    }
}

private final class LocalOnlyDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct CLITaskSnapshot: Decodable {
    struct Row: Identifiable, Decodable {
        let uid, title, note, state: String
        let startAt, dueAt: String?
        var id: String { uid }
        var status: String {
            switch state {
            case "active": "进行中"
            case "completed": "已完成"
            case "archived": "已归档"
            case "abandoned": "已放弃"
            case "abandonedArchived": "放弃后归档"
            default: state
            }
        }
    }
    let version: Int
    let items: [Row]
}

struct CLITaskWindow: View {
    @State private var launcher = CLIAutoLauncher()
    @State private var code = ""
    @State private var connection: CLISession?
    @State private var rows: [CLITaskSnapshot.Row] = []
    @State private var status = ""
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if connection == nil {
                Text("在终端运行 deadliner serve，粘贴连接码以查看 CLI 任务。")
                SecureField("连接码", text: $code)
                    .onSubmit { connect() }
                HStack {
                    Button("连接", action: connect).keyboardShortcut(.defaultAction)
                    Button("尝试自动启动", action: autoConnect)
                }
            } else {
                HStack {
                    TextField("搜索标题或备注", text: $search)
                    Button("断开") { disconnect() }
                }
                List(rows.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search) }) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.title).font(.headline)
                            Spacer()
                            Text(row.status).foregroundStyle(.secondary)
                        }
                        if !row.note.isEmpty { Text(row.note).textSelection(.enabled) }
                        if let due = row.dueAt { Text("截止  " + due).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 260, alignment: .topLeading)
        .task(id: connection) {
            if let connection { await observe(connection) }
        }
        .onAppear { autoConnect() }
        .onDisappear { disconnect() }
    }

    private func autoConnect() {
        status = "正在尝试启动本机 CLI…"
        launcher.start { selected in
            code = ""
            status = "正在连接…"
            connection = selected
        } failed: { message in
            connection = nil
            status = message
        }
    }

    private func connect() {
        guard let selected = CLISession(code: code) else {
            status = "连接码格式有误，请完整复制终端显示的连接码。"
            return
        }
        launcher.stop()
        code = ""
        status = "正在连接…"
        connection = selected
    }

    private func disconnect() {
        launcher.stop()
        connection = nil
        rows = []
        search = ""
        status = ""
        code = ""
    }

    @MainActor
    private func observe(_ selected: CLISession) async {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        let client = URLSession(configuration: config, delegate: LocalOnlyDelegate(), delegateQueue: nil)
        defer { client.invalidateAndCancel() }
        var revision: String?
        while !Task.isCancelled {
            do {
                let (data, response) = try await client.data(for: selected.request(revision: revision))
                guard !Task.isCancelled, connection == selected else { return }
                switch (response as? HTTPURLResponse)?.statusCode {
                case 200:
                    let snapshot = try JSONDecoder().decode(CLITaskSnapshot.self, from: data)
                    guard snapshot.version == 1 else { status = "服务协议不兼容，请断开后更新客户端。"; return }
                    rows = snapshot.items
                    revision = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
                case 304: break
                case 401:
                    status = "连接码已失效，请断开并使用终端的新连接码。"
                    return
                default: throw URLError(.badServerResponse)
                }
                status = "已连接 · \(rows.count) 项任务 · 只读"
            } catch {
                guard !Task.isCancelled, connection == selected else { return }
                status = "服务暂不可用，正在重试。列表保留上次读取的内容。"
            }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }
}
