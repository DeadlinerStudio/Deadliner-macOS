import Foundation

struct CLISession: Equatable {
    let endpoint: URL
    private let token: String

    init?(code: String) {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = UInt16(parts[0]), port > 0,
              parts[1].utf8.count == 64, parts[1].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let url = URL(string: "http://127.0.0.1:\(port)/v1/task-peer") else { return nil }
        endpoint = url
        token = String(parts[1])
    }

    func request(method: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpMethod = method
        return request
    }

    func makeClient() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        return URLSession(configuration: config, delegate: LocalOnlyDelegate(), delegateQueue: nil)
    }

}

private final class LocalOnlyDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
