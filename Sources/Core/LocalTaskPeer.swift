import Foundation
import Shared

/// A local peer uses the same Core merge as WebDAV, with a task-only projection.
@MainActor
final class LocalTaskPeer {
    private let database: DeadlinerDatabase
    private let didImport: () -> Void
    private let launcher = CLIAutoLauncher()
    private var service: CLISession?
    private var worker: Task<Void, Never>?
    private var localGeneration = 0
    private var started = false

    init(database: DeadlinerDatabase, didImport: @escaping () -> Void) {
        self.database = database
        self.didImport = didImport
    }

    func localDidChange() { localGeneration &+= 1 }

    func start() {
        guard !started else { return }
        started = true
        connect()
    }

    private func connect() {
        launcher.start(writable: true) { [weak self] service in
            guard let self, self.started else { return }
            self.attach(service)
        } failed: { [weak self] _ in
            guard let self, self.started else { return }
            self.service = nil
            self.worker?.cancel()
            self.worker = Task {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self.connect()
            }
        }
    }

    func attach(_ peer: CLISession) {
        worker?.cancel()
        started = true
        service = peer
        worker = Task { await observe(peer) }
    }

    func stop() {
        started = false
        service = nil
        worker?.cancel()
        worker = nil
        launcher.stop()
    }

    private func observe(_ peer: CLISession) async {
        let client = peer.makeClient()
        defer { client.invalidateAndCancel() }
        var generation: Int?
        var revision: String?
        var delay = 2
        while !Task.isCancelled {
            do {
                let tag = try await peer.taskRevision(client, known: revision)
                guard started, service == peer, !Task.isCancelled else { return }
                let before = localGeneration
                if before != generation || tag != revision {
                    let exported = database.sync.mergeRemotePayload(remotePayload: nil)
                    guard exported.failureMessage == nil else { throw URLError(.cannotDecodeContentData) }
                    let json = try JSONSerialization.jsonObject(with: Data(exported.payload.utf8))
                    let outgoing = try TaskPeerPayload.project(json)
                    let incoming = try await peer.exchangeTasks(outgoing, using: client)
                    guard started, service == peer, !Task.isCancelled else { return }
                    let merged = database.sync.mergeRemotePayload(remotePayload: incoming)
                    guard merged.failureMessage == nil else { throw URLError(.cannotDecodeContentData) }
                    if merged.remoteApplied > 0 { didImport() }
                    // An edit during the request schedules another exchange on the next tick.
                    generation = before
                    revision = tag
                }
                delay = 2
            } catch {
                delay = min(delay * 2, 60)
            }
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
    }
}
