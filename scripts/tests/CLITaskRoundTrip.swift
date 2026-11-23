import Foundation
import Shared

@main
struct CLITaskRoundTrip {
    @MainActor
    static func main() async throws {
        guard let line = readLine(), let session = CLISession(code: line) else { throw URLError(.badURL) }
        let path = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("mac.sqlite")
        let factory = MacosDatabaseDriverFactory(databasePath: path.path, deviceId: "mac-test")
        let database = DeadlinerDatabase.companion.create(factory: factory)
        defer { database.close() }
        let peer = LocalTaskPeer(database: database) {}
        defer { peer.stop() }
        let commands = TaskCommands(database: database) { peer.localDidChange() }
        try commands.save(TaskDraft(title: "Mac only"))
        peer.attach(session)

        func waitFor(_ predicate: () -> Bool) async throws {
            for _ in 0..<150 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(150))
            }
            throw URLError(.timedOut)
        }

        try await waitFor { commands.item("quality-check")?.title == "上线质量复核" }
        guard var draft = commands.draft(for: "quality-check") else { throw URLError(.cannotParseResponse) }
        draft.note = "Mac 已复核"
        draft.dueAt = nil
        draft.subtasks.append(.init(id: "subtask", content: "复核证据", isCompleted: true))
        try commands.save(draft)
        try await waitFor { commands.draft(for: "quality-check")?.note == "终端已确认" }
        guard commands.item("quality-check")?.subtaskDone == 1 else { throw URLError(.cannotParseResponse) }
        do {
            try commands.save(draft)
            throw URLError(.badServerResponse)
        } catch TaskCommandError.changedWhileEditing {}
    }
}
