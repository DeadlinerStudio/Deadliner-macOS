import Foundation

/// Executed as a separately signed sandboxed bundle on a disposable macOS runner.
@main
struct CLIAutoStartProbe {
    @MainActor
    static func main() async {
        let launcher = CLIAutoLauncher()
        let connected = await withCheckedContinuation { continuation in
            launcher.start { session in
                continuation.resume(returning: session.endpoint.port == 54321)
            } failed: { message in
                print(message)
                continuation.resume(returning: false)
            }
        }
        launcher.stop()
        exit(connected ? 0 : 1)
    }
}
