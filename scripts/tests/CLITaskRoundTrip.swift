import Foundation

@main
struct CLITaskRoundTrip {
    static func main() async throws {
        guard let line = readLine(), let session = CLISession(code: line) else { throw URLError(.badURL) }
        let client = session.makeClient()
        defer { client.invalidateAndCancel() }
        func snapshot() async throws -> CLITaskSnapshot {
            let (data, _) = try await client.data(for: session.request(revision: nil))
            return try JSONDecoder().decode(CLITaskSnapshot.self, from: data)
        }
        let initial = try await snapshot()
        guard initial.writable == true, let task = initial.items.first, task.title == "上线质量复核",
              let revision = task.updatedAt else { throw URLError(.cannotParseResponse) }
        let note = "Mac 已复核"
        try await session.write(op: "update", uid: task.uid, revision: revision, fields: ["note": note, "dueAt": nil])
        do {
            try await session.write(op: "update", uid: task.uid, revision: revision, fields: ["note":"stale"])
            throw URLError(.badServerResponse)
        } catch let error as NSError where error.domain == "DeadlinerCLI" && error.code == 409 {}
        let updated = try await snapshot()
        guard updated.items.first?.note == note, updated.items.first?.dueAt == nil else {
            throw URLError(.cannotParseResponse)
        }
    }
}
