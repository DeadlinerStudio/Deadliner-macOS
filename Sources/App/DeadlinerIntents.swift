import AppIntents
import Foundation

/// 快捷指令（与 iOS 相同的「创建灵感」，另有新建任务、导入分享链接、打开新建窗口）。
/// 指令在应用进程中执行；应用没有运行时系统会在后台启动它。写入走与界面相同的命令，同步照常进行。
enum IntentFailure: LocalizedError {
    case notReady
    var errorDescription: String? { String(localized: "Deadliner 还没有准备好，请先打开应用") }
}

@MainActor
private func appModel() throws -> AppModel {
    guard let model = AppDelegate.current?.model else { throw IntentFailure.notReady }
    return model
}

struct CreateTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "新建任务"
    static let description = IntentDescription("在 Deadliner 中新建一个任务。")
    static let openAppWhenRun = false

    @Parameter(title: "任务名称")
    var name: String

    @Parameter(title: "截止时间")
    var due: Date?

    @Parameter(title: "备注", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("新建任务 \(\.$name)，截止 \(\.$due)") { \.$note }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try appModel()
        var draft = TaskDraft()
        draft.title = name
        draft.note = note
        draft.dueAt = due
        try model.taskCommands.save(draft)
        return .result(dialog: "已添加任务「\(name.trimmingCharacters(in: .whitespacesAndNewlines))」")
    }
}

struct CreateInspirationIntent: AppIntent {
    static let title: LocalizedStringResource = "创建灵感"
    static let description = IntentDescription("把一段文字保存到 Deadliner 灵感箱。")
    static let openAppWhenRun = false

    @Parameter(title: "灵感内容", description: "要保存到 Deadliner 的想法。", inputOptions: String.IntentInputOptions(multiline: true))
    var content: String

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$content) 保存为灵感")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try appModel()
        guard model.capture.create(content) != nil else { return .result(dialog: "内容为空，没有保存") }
        return .result(dialog: "已保存到灵感箱")
    }
}

struct ImportShareLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "导入分享链接"
    static let description = IntentDescription("导入 Deadliner 的任务分享链接（与安卓格式相同），在应用中确认后添加。")
    static let openAppWhenRun = true

    @Parameter(title: "分享链接")
    var link: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try appModel()
        AppDelegate.current?.showMainWindow()
        model.receiveShareLink(link)
        return .result()
    }
}

struct OpenNewTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "打开新建任务"
    static let description = IntentDescription("打开 Deadliner 并显示新建任务窗口。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try appModel()
        AppDelegate.current?.showMainWindow()
        model.newTask()
        return .result()
    }
}

struct DeadlinerShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CreateTaskIntent(),
                    phrases: ["用 \(.applicationName) 新建任务", "在 \(.applicationName) 添加任务"],
                    shortTitle: "新建任务", systemImageName: "plus.circle")
        AppShortcut(intent: CreateInspirationIntent(),
                    phrases: ["用 \(.applicationName) 记录灵感", "在 \(.applicationName) 创建灵感", "把想法存到 \(.applicationName)"],
                    shortTitle: "创建灵感", systemImageName: "lightbulb")
        AppShortcut(intent: OpenNewTaskIntent(),
                    phrases: ["打开 \(.applicationName) 新建任务"],
                    shortTitle: "打开新建任务", systemImageName: "square.and.pencil")
        AppShortcut(intent: ImportShareLinkIntent(),
                    phrases: ["用 \(.applicationName) 导入分享链接"],
                    shortTitle: "导入分享链接", systemImageName: "link")
    }
}
