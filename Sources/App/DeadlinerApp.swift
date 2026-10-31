import SwiftUI

@main
struct DeadlinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Deadliner") {
            BootstrapView(container: appDelegate.container, error: appDelegate.startupError)
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}

/// 持有 Core 容器，保证数据库在整个应用生命周期内只创建一次，退出时关闭。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var container: MacCoreContainer?
    private(set) var startupError: String?

    override init() {
        super.init()
        do {
            container = try MacCoreContainer.makeDefault()
        } catch {
            startupError = error.localizedDescription
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        container?.close()
    }
}

/// 第二步的临时页面：只确认 Core 已接入并能读取数据库，正式界面在后续步骤实现。
struct BootstrapView: View {
    let container: MacCoreContainer?
    let error: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Deadliner for macOS")
                .font(.largeTitle.bold())
            if let container {
                Text("Core：\(MacCoreContainer.coreVersion)")
                    .font(.callout.monospaced())
                Text("本地任务：\(container.database.tasks.list().count) 个")
            } else {
                Text("数据库打开失败：\(error ?? "未知错误")")
                    .foregroundStyle(.red)
            }
        }
        .padding(32)
    }
}
