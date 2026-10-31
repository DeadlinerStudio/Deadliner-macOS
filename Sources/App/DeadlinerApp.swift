import SwiftUI

@main
struct DeadlinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Deadliner") {
            RootView(appDelegate: appDelegate)
                .miuixTheme()
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("刷新") { appDelegate.taskList?.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

/// 持有 Core 容器与各页面的订阅层，保证数据库在整个应用生命周期内只创建一次，退出时关闭。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var container: MacCoreContainer?
    private(set) var taskList: TaskListStore?
    private(set) var startupError: String?

    override init() {
        super.init()
        do {
            let container = try MacCoreContainer.makeDefault()
            self.container = container
            taskList = TaskListStore(database: container.database)
        } catch {
            startupError = error.localizedDescription
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        taskList?.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskList?.stop()
        container?.close()
    }
}

struct RootView: View {
    let appDelegate: AppDelegate
    @Environment(\.miuix) private var t

    var body: some View {
        if let store = appDelegate.taskList {
            TaskListView(store: store)
                .onAppear { store.start() }
        } else {
            Text("数据库打开失败：\(appDelegate.startupError ?? "未知错误")")
                .foregroundStyle(t.error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(t.pageBg)
        }
    }
}
