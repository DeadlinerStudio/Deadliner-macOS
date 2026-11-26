import Foundation

/// Preserve the complete task aggregate and its Core version but never exchange
/// unrelated resources (habits, profiles, memory, etc.) with a local task peer.
enum TaskPeerPayload {
    static func project(_ value: Any) throws -> Data {
        guard let root = value as? [String: Any], let version = root["formatVersion"],
              let snapshot = root["snapshot"] as? [String: Any], snapshot["version"] != nil,
              snapshot["format_version"] != nil else { throw URLError(.cannotParseResponse) }
        let keys = ["version", "format_version", "categories", "tasks"]
        return try JSONSerialization.data(withJSONObject: [
            "formatVersion": version, "snapshot": snapshot.filter { keys.contains($0.key) }
        ])
    }
}

extension CLISession {
    func taskRevision(_ client: URLSession, known: String?) async throws -> String {
        var req = request(method: "HEAD")
        req.setValue(known, forHTTPHeaderField: "If-None-Match")
        let (_, response) = try await client.data(for: req)
        guard let http = response as? HTTPURLResponse, [200,304].contains(http.statusCode),
              let tag = http.value(forHTTPHeaderField: "ETag") else { throw URLError(.badServerResponse) }
        return tag
    }

    func exchangeTasks(_ local: Data, using client: URLSession) async throws -> String {
        var req = request(method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = local
        let (data, response) = try await client.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["ok"] as? Bool == true, let payload = envelope["data"] else { throw URLError(.badServerResponse) }
        return String(decoding: try TaskPeerPayload.project(payload), as: UTF8.self)
    }
}
