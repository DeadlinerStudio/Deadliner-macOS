import SwiftUI

@main
struct DeadlinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Deadliner") {
            RootView(appDelegate: appDelegate)
                .deadlinerTheme()
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建任务") { appDelegate.model?.newTask() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .textEditing) {
                Button("搜索") { appDelegate.model?.searchFocusRequest += 1 }
                    .keyboardShortcut("f", modifiers: [.command])
            }
            CommandMenu("前往") {
                ForEach(Array(AppModel.Page.allCases.enumerated()), id: \.element) { index, page in
                    Button(page.title) { appDelegate.model?.page = page }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }
            }
            CommandGroup(after: .toolbar) {
                Button("立即同步") {
                    appDelegate.model?.refreshAll()
                    appDelegate.model?.sync.syncNow()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        // ⌘, 打开的系统设置窗口（与侧栏中的「设置」页内容相同）。
        Settings {
            if let model = appDelegate.model {
                SettingsView(sync: model.sync)
                    .deadlinerTheme()
                    .frame(width: 640, height: 720)
            }
        }
    }
}

/// 持有应用模型，保证数据库在整个应用生命周期内只创建一次，退出时关闭。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel?
    private(set) var startupError: String?

    /// 作为单元测试的宿主运行时为 true。此时不打开正式数据库、不启动同步，
    /// 避免测试读到用户的同步设置而连接真实的 WebDAV。
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    override init() {
        super.init()
        guard !Self.isRunningTests else {
            startupError = "测试运行中"
            return
        }
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
    @Environment(\.palette) private var t

    @AppStorage(FontPreference.serifKey) private var serif = false

    var body: some View {
        content
            .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
            .fontDesign(serif ? .serif : .default)
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
    @Environment(\.palette) private var t

    var body: some View {
        NavigationSplitView {
            Sidebar(page: $model.page, syncStatus: model.sync.status)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            Group {
                switch model.page {
                case .tasks:
                    TaskListView(store: model.taskList, commands: model.taskCommands, categoryCommands: model.categoryCommands,
                                 onSetupSync: model.sync.status == .disabled ? { model.page = .settings } : nil)
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
            .environment(\.searchFocusRequest, model.searchFocusRequest)
        }
    }
}
