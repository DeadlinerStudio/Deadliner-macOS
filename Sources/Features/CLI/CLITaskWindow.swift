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
    func makeClient() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        return URLSession(configuration: config, delegate: LocalOnlyDelegate(), delegateQueue: nil)
    }

    func write(op: String, uid: String, revision: String?, fields: [String: String?]? = nil) async throws {
        struct Mutation: Encodable {
            let op, uid: String
            let revision: String?
            let fields: [String: String?]?
        }
        var req = request(revision: nil)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Mutation(op: op, uid: uid, revision: revision, fields: fields))
        let client = makeClient()
        defer { client.finishTasksAndInvalidate() }
        let (data, response) = try await client.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            struct Failure: Decodable {
                struct Detail: Decodable { let code, message: String }
                let error: Detail
            }
            let detail = try? JSONDecoder().decode(Failure.self, from: data).error
            let message = detail?.code == "CONFLICT" ? "任务已变更，请核对最新内容后再保存。" :
                detail?.message ?? "操作失败（HTTP "+String(http.statusCode)+"）。"
            throw NSError(domain: "DeadlinerCLI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
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
        let startAt, dueAt, updatedAt: String?
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
    let writable: Bool?
    let items: [Row]
}

struct CLITaskWindow: View {
    var allowsEditing = false
    @Binding var pendingAdd: Bool
    init(allowsEditing: Bool = false, pendingAdd: Binding<Bool> = .constant(false)) {
        self.allowsEditing = allowsEditing
        _pendingAdd = pendingAdd
    }
    @State private var writable = false
    @State private var draft: CLITaskDraft?
    @State private var deleting: CLITaskSnapshot.Row?
    @State private var writeError = ""
    @State private var busy = false
    @State private var launcher = CLIAutoLauncher()
    @State private var code = ""
    @State private var connection: CLISession?
    @State private var rows: [CLITaskSnapshot.Row] = []
    @State private var status = ""
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if connection == nil {
                Text(allowsEditing ? "运行 deadliner serve --allow-writes，粘贴连接码以编辑 CLI 任务。" : "在终端运行 deadliner serve，粘贴连接码以查看 CLI 任务。")
                SecureField("连接码", text: $code)
                    .onSubmit { connect() }
                HStack {
                    Button("连接", action: connect).keyboardShortcut(.defaultAction)
                    Button("尝试自动启动", action: autoConnect)
                }
            } else {
                HStack {
                    TextField("搜索标题或备注", text: $search)
                    if allowsEditing { Button("新建任务") { draft = CLITaskDraft() }.disabled(!writable) }
                    Button("断开") { disconnect() }
                }
                List(rows.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search) }) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.title).font(.headline)
                            Spacer()
                            Text(row.status).foregroundStyle(.secondary)
                            if writable, row.updatedAt != nil {
                                Menu {
                                    Button("编辑") { draft = CLITaskDraft(row) }
                                    if row.state == "active" {
                                        Button("完成") { apply("complete", row) }
                                        Button("放弃") { apply("abandon", row) }
                                    }
                                    if ["completed", "abandoned"].contains(row.state) {
                                        Button("重新打开") { apply("reopen", row) }
                                        Button("归档") { apply("archive", row) }
                                    }
                                    if ["archived", "abandonedArchived"].contains(row.state) {
                                        Button("取消归档") { apply("unarchive", row) }
                                    }
                                    Button("删除…", role: .destructive) { deleting = row }
                                } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.borderlessButton).fixedSize().disabled(busy)
                                .accessibilityLabel("操作：" + row.title)
                            }
                        }
                        if !row.note.isEmpty { Text(row.note).textSelection(.enabled) }
                        if let due = row.dueAt { Text("截止  " + due).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }
            }
            if !writeError.isEmpty { Text(writeError).foregroundStyle(.red) }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 260, alignment: .topLeading)
        .task(id: connection) {
            if let connection { await observe(connection) }
        }
        .sheet(item: $draft) { initial in
            CLITaskEditor(draft: initial, latest: rows.first { $0.uid == initial.id }) { value in
                guard let connection, writable else { throw URLError(.notConnectedToInternet) }
                try await connection.write(op: value.original == nil ? "add" : "update", uid: value.id,
                                           revision: value.original?.updatedAt, fields: value.fields)
            }
        }
        .alert("删除这条 CLI 任务？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { row in
            Button("删除", role: .destructive) { apply("delete", row) }
            Button("取消", role: .cancel) {}
        } message: { row in Text(row.title) }
        .onChange(of: pendingAdd) { openPendingDraft() }
        .onChange(of: writable) { openPendingDraft() }
        .onAppear { autoConnect() }
        .onDisappear { disconnect() }
    }

    private func openPendingDraft() {
        guard pendingAdd, writable else { return }
        pendingAdd = false
        draft = CLITaskDraft()
    }

    private func apply(_ op: String, _ row: CLITaskSnapshot.Row) {
        guard let connection, writable, !busy else { return }
        busy = true
        writeError = ""
        Task {
            defer { busy = false }
            do { try await connection.write(op: op, uid: row.uid, revision: row.updatedAt) }
            catch { if self.connection == connection { writeError = error.localizedDescription } }
        }
    }

    private func autoConnect() {
        status = "正在尝试启动本机 CLI…"
        launcher.start(writable: allowsEditing) { selected in
            code = ""
            status = "正在连接…"
            connection = selected
        } failed: { message in
            disconnect()
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
        writable = false
        draft = nil
        deleting = nil
        writeError = ""
        rows = []
        search = ""
        status = ""
        code = ""
    }

    @MainActor
    private func observe(_ selected: CLISession) async {
        let client = selected.makeClient()
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
                    writable = allowsEditing && snapshot.writable == true
                    revision = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
                case 304: break
                case 401:
                    writable = false
                    status = "连接码已失效，请断开并使用终端的新连接码。"
                    return
                default: throw URLError(.badServerResponse)
                }
                status = "已连接 · \(rows.count) 项任务 · " + (writable ? "可编辑" : "只读")
            } catch {
                guard !Task.isCancelled, connection == selected else { return }
                writable = false
                revision = nil
                status = "服务暂不可用，正在重试。列表保留上次读取的内容。"
            }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }
}
