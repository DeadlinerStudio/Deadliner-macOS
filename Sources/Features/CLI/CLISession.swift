import Foundation

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
    }
    let version: Int
    let writable: Bool?
    let items: [Row]
}
