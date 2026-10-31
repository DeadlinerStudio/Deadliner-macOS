import SwiftUI

@main
struct DeadlinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Deadliner") {
            RootView(appDelegate: appDelegate)
                .miuixTheme()
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建任务") { appDelegate.model?.newTask() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
                Button("立即同步") {
                    appDelegate.model?.refreshAll()
                    appDelegate.model?.sync.syncNow()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

/// 持有应用模型，保证数据库在整个应用生命周期内只创建一次，退出时关闭。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel?
    private(set) var startupError: String?

    override init() {
        super.init()
        do {
            model = AppModel(container: try MacCoreContainer.makeDefault())
        } catch {
            startupError = error.localizedDescription
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshAll()
        model?.sync.setForeground(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        model?.sync.setForeground(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }
}

struct RootView: View {
    let appDelegate: AppDelegate
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @Environment(\.miuix) private var t

    var body: some View {
        content.preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        if let model = appDelegate.model {
            MainView(model: model)
                .onAppear { model.start() }
        } else {
            Text("数据库打开失败：\(appDelegate.startupError ?? "未知错误")")
                .foregroundStyle(t.error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(t.pageBg)
        }
    }
}

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.miuix) private var t

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(page: $model.page)
            Group {
                switch model.page {
                case .tasks:
                    TaskListView(store: model.taskList, commands: model.taskCommands, categoryCommands: model.categoryCommands)
                case .habits:
                    HabitsView(store: model.habitList, commands: model.habitCommands, categories: model.taskList.categories)
                case .focus:
                    FocusView(store: model.focus)
                case .archive:
                    ArchiveView(store: model.archive, commands: model.taskCommands)
                case .settings:
                    SettingsView(sync: model.sync)
                }
            }
            .padding(.top, 24)
            .background(t.pageBg)
        }
        .background(t.pageBg)
        .ignoresSafeArea(.container, edges: .top)
    }
}
