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
                Button("快速添加") {
                    appDelegate.showMainWindow()
                    appDelegate.model?.showingQuickAdd = true
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Lifi AI") { appDelegate.openLifiAction?() }
                    .keyboardShortcut("l", modifiers: [.command])
            }
            CommandGroup(after: .textEditing) {
                Button("搜索") { appDelegate.model?.searchFocusRequest += 1 }
                    .keyboardShortcut("f", modifiers: [.command])
            }
            CommandGroup(after: .pasteboard) {
                Button("从剪贴板导入分享链接") {
                    appDelegate.showMainWindow()
                    appDelegate.model?.importShareLinkFromPasteboard()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
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

        // 专注计时窗：可以置顶，关闭窗口不会结束计时。
        Window("专注", id: FocusTimerWindow.id) {
            if let model = appDelegate.model {
                FocusTimerWindowView(timer: model.focusTimer)
                    .modifier(AppearancePreferences())
                    .deadlinerTheme()
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        // Lifi AI 对话窗口。
        Window("Lifi AI", id: LifiWindow.id) {
            if let model = appDelegate.model {
                LifiAssistantView(store: model.lifi, openSettings: {
                    UserDefaults.standard.set(SettingsCategory.lifi.rawValue, forKey: SettingsCategory.storageKey)
                    appDelegate.showMainWindow()
                    model.page = .settings
                })
                .modifier(AppearancePreferences())
                .deadlinerTheme()
            }
        }
        .defaultSize(width: 480, height: 640)

        // 每日概览弹窗（设置中开启）。
        Window("今日概览", id: DailyBriefSettings.windowId) {
            if let model = appDelegate.model {
                DailyBriefView(model: model)
                    .modifier(AppearancePreferences())
                    .deadlinerTheme()
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // ⌘, 打开的系统设置窗口（与侧栏中的「设置」页内容相同）。
        Settings {
            if let model = appDelegate.model {
                SettingsView(sync: model.sync, backup: LocalBackup(database: model.container.database), notifications: model.notifications, onBackupImported: { model.refreshAll() }, lifiDatabase: model.container.database)
                    .modifier(AppearancePreferences())
                    .deadlinerTheme()
                    .frame(width: 800, height: 620)
            }
        }
    }
}

/// 持有应用模型，保证数据库在整个应用生命周期内只创建一次，退出时关闭。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 当前应用的委托（快捷指令在应用进程内执行时用来取得数据）。
    private(set) static weak var current: AppDelegate?
    private(set) var model: AppModel?
    private(set) var startupError: String?
    private var menuBar: MenuBarController?
    /// 由主窗口内容在出现时提供，用于在主窗口关闭后从菜单栏重新打开它。
    var openMainWindowAction: (() -> Void)?
    /// 打开专注计时窗（倒计时结束的通知点开时使用）。
    var openFocusWindowAction: (() -> Void)?
    /// 打开每日概览弹窗。
    var openDailyBriefAction: (() -> Void)?
    /// 打开 Lifi AI 对话窗口。
    var openLifiAction: (() -> Void)?
    private var dailyBrief: DailyBriefController?

    /// 作为单元测试的宿主运行时为 true。此时不打开正式数据库、不启动同步，
    /// 避免测试读到用户的同步设置而连接真实的 WebDAV。
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    override init() {
        super.init()
        Self.current = self
        guard !Self.isRunningTests else {
            startupError = "测试运行中"
            return
        }
        do {
            let model = AppModel(container: try MacCoreContainer.makeDefault())
            // 已经设置过同步的用户（更新前就在使用）不再显示新手引导。
            if model.sync.settings.enabled, UserDefaults.standard.object(forKey: Onboarding.doneKey) == nil {
                UserDefaults.standard.set(true, forKey: Onboarding.doneKey)
            }
            self.model = model
        } catch {
            startupError = error.localizedDescription
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model else { return }
        AppearancePreferences.apply(UserDefaults.standard.string(forKey: "appearance") ?? AppearanceMode.system.rawValue)
        menuBar = MenuBarController(model: model) { [weak self] in self?.showMainWindow() }
        let notifications = NotificationController(database: model.container.database) { [weak self, weak model] _, kind in
            if kind == "FOCUS_TIMER" {
                NSApp.activate(ignoringOtherApps: true)
                self?.openFocusWindowAction?()
                return
            }
            model?.page = kind.hasPrefix("HABIT") ? .habits : kind == DailySummary.kind ? .overview : .tasks
            self?.showMainWindow()
        }
        notifications.start()
        model.notifications = notifications
        // 主窗口内容出现后才有打开窗口的入口，稍后再开始判断。
        DispatchQueue.main.async { [weak self] in
            let brief = DailyBriefController { [weak self] in
                guard let open = self?.openDailyBriefAction else { return false }
                NSApp.activate(ignoringOtherApps: true)
                open()
                return true
            }
            brief.start()
            self?.dailyBrief = brief
        }
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
        model?.focusTimer.reconcile()
        model?.sync.setForeground(true)
        model?.notifications?.refresh()
        model?.checkPasteboardForShareLink()
    }

    func applicationDidResignActive(_ notification: Notification) {
        model?.sync.setForeground(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dailyBrief?.stop()
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
                    appDelegate.openFocusWindowAction = { openWindow(id: FocusTimerWindow.id) }
                    appDelegate.openDailyBriefAction = { openWindow(id: DailyBriefSettings.windowId) }
                    appDelegate.openLifiAction = {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: LifiWindow.id)
                    }
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
    @State private var editingProfile = false
    @State private var timerConflictError: String?
    @AppStorage(Onboarding.doneKey) private var onboardingDone = false
    @Environment(\.palette) private var t

    var body: some View {
        NavigationSplitView {
            Sidebar(page: $model.page, syncStatus: model.sync.status, syncNow: { model.sync.syncNow() },
                    profile: model.profile, editProfile: { editingProfile = true },
                    taskList: model.taskList, habitList: model.habitList)
                .displayScaled()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            Group {
                switch model.page {
                case .tasks:
                    TaskListView(store: model.taskList, commands: model.taskCommands, categoryCommands: model.categoryCommands,
                                 onQuickAdd: { model.showingQuickAdd = true },
                                 onLifi: LifiSettings.isAvailable ? { AppDelegate.current?.openLifiAction?() } : nil,
                                 onSetupSync: model.sync.status == .disabled ? { model.page = .settings } : nil,
                                 archiveMatches: { model.archive.taskMatchCount($0) },
                                 onShowArchive: { query in
                                     model.archive.searchText = query
                                     model.page = .archive
                                 })
                case .habits:
                    HabitsView(store: model.habitList, commands: model.habitCommands, categories: model.taskList.categories)
                case .capture:
                    CaptureView(store: model.capture, taskCommands: model.taskCommands, categoryCommands: model.categoryCommands,
                                habitCommands: model.habitCommands, categories: model.taskList.categories)
                case .overview:
                    OverviewView(store: model.overview)
                case .focus:
                    FocusView(store: model.focus)
                case .archive:
                    ArchiveView(store: model.archive, commands: model.taskCommands)
                case .settings:
                    SettingsView(sync: model.sync, backup: LocalBackup(database: model.container.database), notifications: model.notifications, onBackupImported: { model.refreshAll() }, lifiDatabase: model.container.database)
                }
            }
            .displayScaled()
            .environment(\.searchFocusRequest, model.searchFocusRequest)
            .environment(\.focusTimer, model.focusTimer)
        }
        .sheet(isPresented: $model.showingQuickAdd) {
            QuickAddSheet(lifi: model.lifi, taskCommands: model.taskCommands, habitCommands: model.habitCommands,
                          openTaskEditor: { draft in
                              model.showingQuickAdd = false
                              DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                  model.page = .tasks
                                  model.taskList.editor = .init(draft: draft)
                              }
                          },
                          openHabitEditor: { draft in
                              model.showingQuickAdd = false
                              DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                  model.page = .habits
                                  model.habitList.editor = .init(draft: draft)
                              }
                          },
                          onAdded: { _ in model.showingQuickAdd = false },
                          onClose: { model.showingQuickAdd = false })
            .deadlinerTheme()
        }
        .sheet(isPresented: $editingProfile) {
            ProfileSheet(store: model.profile) { editingProfile = false }.deadlinerTheme()
        }
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingView(openSyncSettings: { model.page = .settings },
                           notificationsChanged: { model.notifications?.refresh(force: true) },
                           finish: { onboardingDone = true })
                .deadlinerTheme()
                .interactiveDismissDisabled()
        }
        .confirmationDialog(
            model.timerConflict.map { "「\($0.title)」正在专注计时" } ?? "",
            isPresented: Binding(get: { model.timerConflict != nil }, set: { if !$0 { model.timerConflict = nil } }),
            presenting: model.timerConflict
        ) { conflict in
            Button("结束专注并继续") {
                model.resolveTimerConflict(conflict) { message in timerConflictError = message }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("会先结束并保存这次专注，再执行刚才的操作。")
        }
        .overlay { CelebrationOverlay(trigger: model.celebration) }
        .overlay(alignment: .bottom) {
            if let undo = model.undoCompletion {
                HStack(spacing: 12) {
                    Label("已完成\(undo.title)", systemImage: "checkmark.circle.fill")
                        .lineLimit(1)
                    Button("撤销") { model.undoLastCompletion() }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("z", modifiers: [.command])
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .deadlinerGlass(in: Capsule())
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.undoCompletion)
        .alert(shareAlertTitle, isPresented: Binding(get: { model.pendingShare != nil }, set: { if !$0 { model.pendingShare = nil } }),
               presenting: model.pendingShare) { share in
            switch share.result {
            case .success(let draft):
                Button("添加") { model.acceptShare(draft) }
                Button("取消", role: .cancel) {}
            case .failure:
                Button("好", role: .cancel) {}
            }
        } message: { share in
            switch share.result {
            case .success(let draft): Text(Self.shareSummary(draft))
            case .failure(let error): Text(error.localizedDescription)
            }
        }
        .alert("无法完成操作", isPresented: Binding(get: { timerConflictError != nil }, set: { if !$0 { timerConflictError = nil } })) {
            Button("好") {}
        } message: {
            Text(timerConflictError ?? "")
        }
    }

    private var shareAlertTitle: String {
        if case .failure = model.pendingShare?.result { return "无法导入分享链接" }
        return "检测到分享链接"
    }

    /// 导入前的确认文字：任务名、截止时间和子任务数。
    static func shareSummary(_ draft: TaskDraft) -> String {
        var lines = ["「\(draft.title)」"]
        if let due = draft.dueAt { lines.append("截止：\(due.formatted(.dateTime.year().month().day().hour().minute()))") }
        if !draft.subtasks.isEmpty { lines.append("\(draft.subtasks.count) 个子任务") }
        lines.append("添加后会打开编辑窗口，保存后才会写入。")
        return lines.joined(separator: "\n")
    }
}

enum LifiWindow {
    static let id = "lifi"
}
