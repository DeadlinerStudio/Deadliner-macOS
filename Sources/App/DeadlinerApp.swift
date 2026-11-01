import SwiftUI

@main
struct DeadlinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Deadliner", id: "main") {
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
                SettingsView(sync: model.sync, backup: LocalBackup(database: model.container.database), notifications: model.notifications)
                    .modifier(AppearancePreferences())
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
    private var menuBar: MenuBarController?
    /// 由主窗口内容在出现时提供，用于在主窗口关闭后从菜单栏重新打开它。
    var openMainWindowAction: (() -> Void)?

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model else { return }
        AppearancePreferences.apply(UserDefaults.standard.string(forKey: "appearance") ?? AppearanceMode.system.rawValue)
        menuBar = MenuBarController(model: model) { [weak self] in self?.showMainWindow() }
        let notifications = NotificationController(database: model.container.database) { [weak self, weak model] _, kind in
            model?.page = kind.hasPrefix("HABIT") ? .habits : .tasks
            self?.showMainWindow()
        }
        notifications.start()
        model.notifications = notifications
    }

    /// 激活应用并显示主窗口；主窗口已关闭时重新打开。
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshAll()
        model?.sync.setForeground(true)
        model?.notifications?.refresh()
    }

    func applicationDidResignActive(_ notification: Notification) {
        model?.sync.setForeground(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.tearDown()
        model?.stop()
    }
}

/// 用户的外观偏好（深浅色、衬线字体），主窗口与设置窗口共用。
struct AppearancePreferences: ViewModifier {
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage(FontPreference.serifKey) private var serif = false

    func body(content: Content) -> some View {
        // 外观设在 NSApp 上而不是 preferredColorScheme：后者从深色改回 nil 时，
        // 窗口里已经渲染的部分不会恢复跟随系统（表单仍是深色、侧栏变浅色）。
        content
            .fontDesign(serif ? .serif : .default)
            .onAppear { Self.apply(appearance) }
            .onChange(of: appearance) { Self.apply(appearance) }
    }

    static func apply(_ raw: String) {
        NSApp.appearance = switch AppearanceMode(rawValue: raw) ?? .system {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct RootView: View {
    let appDelegate: AppDelegate
    @Environment(\.palette) private var t

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content.modifier(AppearancePreferences())
    }

    @ViewBuilder
    private var content: some View {
        if let model = appDelegate.model {
            MainView(model: model)
                .onAppear {
                    model.start()
                    appDelegate.openMainWindowAction = { openWindow(id: "main") }
                }
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
            Sidebar(page: $model.page, syncStatus: model.sync.status, syncNow: { model.sync.syncNow() })
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            Group {
                switch model.page {
                case .tasks:
                    TaskListView(store: model.taskList, commands: model.taskCommands, categoryCommands: model.categoryCommands,
                                 onSetupSync: model.sync.status == .disabled ? { model.page = .settings } : nil)
                case .habits:
                    HabitsView(store: model.habitList, commands: model.habitCommands, categories: model.taskList.categories)
                case .overview:
                    OverviewView(store: model.overview)
                case .focus:
                    FocusView(store: model.focus)
                case .archive:
                    ArchiveView(store: model.archive, commands: model.taskCommands)
                case .settings:
                    SettingsView(sync: model.sync, backup: LocalBackup(database: model.container.database), notifications: model.notifications)
                }
            }
            .environment(\.searchFocusRequest, model.searchFocusRequest)
        }
    }
}
