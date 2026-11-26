import Foundation

/// A user-installed script starts the CLI and binds its lifetime to the input pipe.
@MainActor
final class CLIAutoLauncher {
    private var control: FileHandle?
    private var script: NSUserUnixTask?
    private var reader: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    private struct Handshake: Decodable {
        struct Payload: Decodable { let connectionCode: String }
        let ok: Bool
        let version: Int
        let data: Payload
    }

    func start(ready: @escaping @MainActor (CLISession) -> Void, failed: @escaping @MainActor (String) -> Void) {
        stop()
        let id = generation
        do {
            let directory = try FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: false)
            let file = directory.appendingPathComponent("deadliner-readonly")
            guard FileManager.default.isExecutableFile(atPath: file.path) else {
                failed("未配置自动启动，可手动输入连接码。")
                return
            }
            let task = try NSUserUnixTask(url: file)
            let input = Pipe(), output = Pipe()
            control = input.fileHandleForWriting
            script = task
            task.standardInput = input.fileHandleForReading
            task.standardOutput = output.fileHandleForWriting
            task.execute(withArguments: []) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == id else { return }
                    self.stop()
                    failed("自动启动的 CLI 服务已退出。可重试或手动连接。")
                }
            }
            let stream = output.fileHandleForReading
            reader = Task { [weak self] in
                do {
                    var data = Data()
                    for try await byte in stream.bytes {
                        if byte == 10 { break }
                        guard data.count < 4096 else { throw CocoaError(.fileReadCorruptFile) }
                        data.append(byte)
                    }
                    let reply = try JSONDecoder().decode(Handshake.self, from: data)
                    guard reply.ok, reply.version == 1, let session = CLISession(code: reply.data.connectionCode)
                    else { throw CocoaError(.fileReadCorruptFile) }
                    guard let self, self.generation == id else { return }
                    self.timeout?.cancel()
                    ready(session)
                } catch {
                    guard let self, self.generation == id else { return }
                    self.stop()
                    failed("CLI 未返回有效连接码，可手动连接。")
                }
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                guard let self, self.generation == id else { return }
                self.stop()
                failed("自动启动超时，可重试或手动连接。")
            }
        } catch {
            stop()
            failed("无法启动 CLI，可手动输入连接码。")
        }
    }

    func stop() {
        generation = UUID()
        try? control?.close()
        control = nil
        script = nil
        reader?.cancel()
        reader = nil
        timeout?.cancel()
        timeout = nil
    }
}
