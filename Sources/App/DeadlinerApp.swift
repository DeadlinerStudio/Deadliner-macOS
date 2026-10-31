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
            CommandGroup(replacing: .newItem) {
                Button("新建任务") { appDelegate.taskList?.editor = .init(draft: TaskDraft()) }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
                Button("刷新") { appDelegate.taskList?.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

/// 持有 Core 容器与各页面的订阅层、写入命令，保证数据库在整个应用生命周期内只创建一次，退出时关闭。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var container: MacCoreContainer?
    private(set) var taskList: TaskListStore?
    private(set) var taskCommands: TaskCommands?
    private(set) var categoryCommands: CategoryCommands?
    private(set) var startupError: String?

    override init() {
        super.init()
        do {
            let container = try MacCoreContainer.makeDefault()
            let taskList = TaskListStore(database: container.database)
            self.container = container
            self.taskList = taskList
            taskCommands = TaskCommands(database: container.database) { [weak taskList] in taskList?.refresh() }
            categoryCommands = CategoryCommands(database: container.database) { [weak taskList] in taskList?.refresh() }
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
        if let store = appDelegate.taskList, let commands = appDelegate.taskCommands, let categories = appDelegate.categoryCommands {
            TaskListView(store: store, commands: commands, categoryCommands: categories)
                .onAppear { store.start() }
        } else {
            Text("数据库打开失败：\(appDelegate.startupError ?? "未知错误")")
                .foregroundStyle(t.error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(t.pageBg)
        }
    }
}
