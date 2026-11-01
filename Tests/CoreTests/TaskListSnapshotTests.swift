import XCTest
import SwiftUI
@testable import DeadlinerTestHost

/// 用占位数据渲染任务页截图（浅色 / 深色），供人工对照手机界面。
/// 截图保存在测试进程临时目录下的 `deadliner-snapshots/`，路径会打印到测试日志。
@MainActor
final class TaskListSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRenderTaskListLightAndDark() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, tokens, scheme) in [("tasks-light", DeadlinerPalette.light, ColorScheme.light), ("tasks-dark", DeadlinerPalette.dark, ColorScheme.dark)] {
            let view = TaskListContent(
                tasks: TaskListStore.sorted(sampleTasks, by: .dueDate),
                totalCount: sampleTasks.count,
                categories: sampleCategories,
                isLoading: false,
                errorMessage: nil,
                searchText: "",
                now: now
            )
            .environment(\.palette, tokens)
            .environment(\.colorScheme, scheme)

            // ImageRenderer 画不出 ScrollView / TextField，改为放进屏幕外的真实窗口后抓取位图。
            let size = NSSize(width: 1180, height: 560)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderBack(nil)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            hosting.layoutSubtreeIfNeeded()

            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            window.orderOut(nil)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let url = directory.appendingPathComponent("\(name).png")
            try png.write(to: url)
            print("SNAPSHOT \(url.path)")
        }
    }

    /// 编辑器与分类管理的截图（使用临时数据库，数据为占位内容）。
    func testRenderEditorAndCategoryManager() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-snapshot-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = MacCoreContainer(databaseURL: directory.appendingPathComponent("db.sqlite"), deviceId: "snapshot")
        defer { container.close() }
        let commands = TaskCommands(database: container.database) {}
        let categoryCommands = CategoryCommands(database: container.database) {}
        let draft = TaskDraft(
            id: "preview", title: "示例任务 A", note: "示例备注", startAt: nil, dueAt: now.addingTimeInterval(86400 * 3),
            categoryId: categoryCommands.list().first?.id, isStarred: true,
            subtasks: [.init(id: "1", content: "子任务一", isCompleted: true), .init(id: "2", content: "子任务二", isCompleted: false)]
        )
        for (scheme, tokens) in [(ColorScheme.light, DeadlinerPalette.light), (ColorScheme.dark, DeadlinerPalette.dark)] {
            let suffix = scheme == .dark ? "dark" : "light"
            try capture(
                TaskEditorSheet(commands: commands, categoryCommands: categoryCommands, draft: draft) {}
                    .environment(\.palette, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 520, height: 660), scheme: scheme, name: "editor-\(suffix)"
            )
            try capture(
                CategoryManagerSheet(commands: categoryCommands) {}
                    .environment(\.palette, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 480, height: 560), scheme: scheme, name: "categories-\(suffix)"
            )
        }
    }

    /// 习惯页、归档页与带侧栏的整体布局截图（占位数据）。
    func testRenderHabitsArchiveAndSidebar() throws {
        func habit(_ id: String, _ name: String, done: Int, target: Int, kind: HabitItem.ActionKind = .checkOff, unit: String? = nil,
                   window: HabitItem.GoalWindow = .scheduledDay, due: Bool = true, completed: Bool = false, category: String? = nil) -> HabitItem {
            HabitItem(id: id, name: name, note: "", colorHex: nil, categoryId: category, doneCount: done, targetCount: target,
                      isCompleted: completed, canApplyPrimaryAction: due, actionKind: kind, actionAmount: kind == .addQuantity ? 250 : 1,
                      unit: unit, goalWindow: window, scheduleKind: .weeklyDays, weekdaysMask: nil, isDue: due,
                      dueReason: due ? "DUE" : "WEEKDAY_NOT_SELECTED", hintKind: nil, daysUntil: nil)
        }
        let calendar = Calendar.current
        let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let week = (0..<7).map { offset -> HabitDay in
            let date = HabitDates.string(calendar.date(byAdding: .day, value: offset, to: monday)!)
            return HabitDay(date: date, completed: offset % 3, total: 3, fraction: Double(offset % 3) / 3)
        }
        let selected = week[3].date
        let habitsView = HabitsContent(
            daily: [habit("1", "示例习惯 A", done: 1, target: 1, completed: true, category: "c2"),
                    habit("2", "示例习惯 B", done: 500, target: 2000, kind: .addQuantity, unit: "ml"),
                    habit("3", "示例习惯 C", done: 0, target: 1, category: "c3")],
            period: [habit("4", "示例习惯 D", done: 2, target: 3, window: .week)],
            upcoming: [habit("5", "示例习惯 E", done: 0, target: 1, due: false)],
            week: week, selectedDate: selected, categories: sampleCategories, isLoading: false, errorMessage: nil,
            searchText: ""
        )
        let archiveView = ArchiveContent(
            tasks: Array(sampleTasks.prefix(2)).map { var task = $0; task.state = .archived; return task },
            habits: [.init(id: "h", name: "示例习惯 F", colorHex: "#10B981", categoryId: nil)],
            categories: sampleCategories
        )
        for (scheme, tokens) in [(ColorScheme.light, DeadlinerPalette.light), (ColorScheme.dark, DeadlinerPalette.dark)] {
            let suffix = scheme == .dark ? "dark" : "light"
            try capture(
                HStack(spacing: 0) { Sidebar(page: .constant(.habits)); habitsView }
                    .environment(\.palette, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 1240, height: 680), scheme: scheme, name: "habits-\(suffix)"
            )
            try capture(
                archiveView.environment(\.palette, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 1000, height: 480), scheme: scheme, name: "archive-\(suffix)"
            )
        }
    }

    /// 习惯编辑器与专注页截图（占位数据）。
    func testRenderHabitEditorAndFocus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-snapshot-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = MacCoreContainer(databaseURL: directory.appendingPathComponent("db.sqlite"), deviceId: "snapshot")
        defer { container.close() }
        var draft = HabitDraft()
        draft.id = "preview"
        draft.name = "示例习惯 A"
        draft.colorHex = "#10B981"
        draft.weekdaysMask = 0b001_0101
        draft.trackingMode = .quantity
        draft.unit = "ml"
        draft.defaultIncrement = 250
        draft.targetCount = 2000
        draft.reminderEnabled = true
        let categories = CategoryCommands(database: container.database) {}.list()
        let sessions: [FocusStore.Session] = (0..<5).map { index in
            let start = now.addingTimeInterval(Double(-index) * 9000)
            return .init(id: "\(index)", title: "示例任务 \(index + 1)", isHabit: index == 2, isCountdown: index % 2 == 0,
                         startedAt: start, endedAt: start.addingTimeInterval(1500), durationSeconds: 1500,
                         completionKind: index == 0 ? "FOCUS_AND_TASK_COMPLETED" : "FOCUS_ONLY")
        }
        for (scheme, tokens) in [(ColorScheme.light, DeadlinerPalette.light), (ColorScheme.dark, DeadlinerPalette.dark)] {
            let suffix = scheme == .dark ? "dark" : "light"
            try capture(
                HabitEditorSheet(commands: HabitCommands(database: container.database) {}, categories: categories, draft: draft) {}
                    .environment(\.palette, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 540, height: 700), scheme: scheme, name: "habit-editor-\(suffix)"
            )
            try capture(
                FocusContent(today: .init(totalSeconds: 3000, sessionCount: 2), thisWeek: .init(totalSeconds: 27000, sessionCount: 14),
                             thisMonth: .init(totalSeconds: 90000, sessionCount: 51), allTime: .init(totalSeconds: 540000, sessionCount: 300),
                             sessions: sessions)
                    .environment(\.palette, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 1000, height: 640), scheme: scheme, name: "focus-\(suffix)"
            )
        }
    }

    /// 设置页截图（隔离的 UserDefaults 与钥匙串，不含任何真实服务器信息）。
    func testRenderSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-snapshot-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = MacCoreContainer(databaseURL: directory.appendingPathComponent("db.sqlite"), deviceId: "snapshot")
        defer { container.close() }
        let defaults = UserDefaults(suiteName: "deadliner-snapshot-\(UUID().uuidString)")!
        SyncSettings(serverURL: "https://dav.example.com/dav/", username: "user@example.com", enabled: false).save(to: defaults)
        let sync = SyncController(database: container.database,
                                  keychain: KeychainPasswordStore(service: "com.deadliner.macos.snapshot.\(UUID().uuidString)"),
                                  defaults: defaults) {}
        for (scheme, tokens) in [(ColorScheme.light, DeadlinerPalette.light), (ColorScheme.dark, DeadlinerPalette.dark)] {
            try capture(
                SettingsView(sync: sync).environment(\.palette, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 820, height: 900), scheme: scheme, name: "settings-\(scheme == .dark ? "dark" : "light")"
            )
        }
    }

    /// 整窗截图：真实的 AppModel + 临时数据库（占位数据），逐页截取。
    func testRenderFullWindowPages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(container: MacCoreContainer(databaseURL: directory.appendingPathComponent("db.sqlite"), deviceId: "window"))
        defer { model.stop() }

        let categories = model.categoryCommands.list()
        let calendar = Calendar.current
        let inDays = { (days: Double) in Date().addingTimeInterval(days * 86400) }
        let drafts: [TaskDraft] = [
            TaskDraft(title: "示例任务 A", note: "示例备注", dueAt: inDays(3), categoryId: categories[0].id, isStarred: true,
                      subtasks: [.init(id: "s1", content: "一", isCompleted: true), .init(id: "s2", content: "二", isCompleted: false)]),
            TaskDraft(title: "示例任务 B", dueAt: inDays(0.2), categoryId: categories[1].id),
            TaskDraft(title: "示例任务 C", dueAt: inDays(-1), categoryId: categories[2].id),
            TaskDraft(title: "示例任务 D", startAt: inDays(2), dueAt: inDays(9)),
            TaskDraft(title: "示例任务 E", dueAt: inDays(14)),
        ]
        for draft in drafts { try model.taskCommands.save(draft) }
        var habit = HabitDraft()
        habit.name = "示例习惯 A"
        habit.startOn = calendar.date(byAdding: .day, value: -7, to: Date())!
        try model.habitCommands.save(habit)
        habit.name = "示例习惯 B"
        habit.trackingMode = .quantity
        habit.unit = "ml"
        habit.defaultIncrement = 250
        habit.targetCount = 2000
        try model.habitCommands.save(habit)
        model.start()

        for (scheme, tokens) in [(ColorScheme.light, DeadlinerPalette.light), (ColorScheme.dark, DeadlinerPalette.dark)] {
            for page in [AppModel.Page.tasks, .habits, .settings] {
                model.page = page
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                try capture(
                    MainView(model: model).environment(\.palette, tokens).environment(\.colorScheme, scheme),
                    size: NSSize(width: 1280, height: 760), scheme: scheme,
                    name: "window-\(page.rawValue)-\(scheme == .dark ? "dark" : "light")", titled: true
                )
            }
        }
    }

    /// 菜单栏面板（两种风格，Liquid Glass 与旧系统毛玻璃）与菜单栏样式截图（占位数据）。
    func testRenderMenuBarPanelAndLabels() throws {
        func habit(_ id: String, _ name: String, done: Int, target: Int, quantity: Bool = false) -> HabitItem {
            HabitItem(id: id, name: name, note: "", colorHex: nil, categoryId: nil, doneCount: done, targetCount: target,
                      isCompleted: done >= target, canApplyPrimaryAction: true, actionKind: quantity ? .addQuantity : .checkOff,
                      actionAmount: quantity ? 250 : 1, unit: quantity ? "ml" : nil, goalWindow: .scheduledDay, scheduleKind: .weeklyDays,
                      weekdaysMask: nil, isDue: true, dueReason: "DUE", hintKind: nil, daysUntil: nil)
        }
        let now = self.now
        let focusDays = (0..<7).map { FocusStore.DayPoint(date: HabitDates.string(now.addingTimeInterval(Double($0 - 6) * 86400)), seconds: [1800, 5400, 0, 7200, 3600, 9000, 2400][$0]) }
        let summary = MenuBarSummary.make(
            tasks: sampleTasks, habits: [habit("h1", "示例习惯 A", done: 1, target: 1), habit("h2", "示例习惯 B", done: 500, target: 2000, quantity: true)],
            today: HabitDay(date: "x", completed: 1, total: 2, fraction: 0.5), focusTodaySeconds: 4800, focusDays: focusDays, now: now
        )
        for (scheme, tokens) in [(ColorScheme.light, DeadlinerPalette.light), (ColorScheme.dark, DeadlinerPalette.dark)] {
            let suffix = scheme == .dark ? "dark" : "light"
            for style in PanelStyle.allCases {
                for legacy in [false, true] {
                    try capture(
                        MenuBarPanelContent(summary: summary, style: style, sections: PanelSection.defaults, syncStatus: .succeeded(now), now: now)
                            .padding(30)
                            .background(LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .environment(\.palette, tokens).environment(\.colorScheme, scheme).environment(\.forceLegacyGlass, legacy),
                        size: NSSize(width: 440, height: 860), scheme: scheme,
                        name: "menubar-\(style.rawValue)-\(suffix)\(legacy ? "-legacy" : "")"
                    )
                }
            }
            // 自定义数据格、「本周」范围与横向专注图表。
            try capture(
                MenuBarPanelContent(summary: summary, style: .dashboard, sections: PanelSection.defaults, syncStatus: .succeeded(now), now: now,
                                    focusOrientation: .horizontal, stats: [.dueTomorrow, .pendingThisWeek, .activeThisWeek, .focusThisWeek],
                                    upcomingRange: .week)
                    .padding(30)
                    .background(LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .environment(\.palette, tokens).environment(\.colorScheme, scheme).environment(\.forceLegacyGlass, true),
                size: NSSize(width: 440, height: 900), scheme: scheme, name: "menubar-custom-\(suffix)"
            )
            try capture(
                VStack(alignment: .trailing, spacing: 14) {
                    ForEach(StatusItemStyle.allCases) { style in
                        StatusLabelView(summary: summary, style: style, fields: [.today, .overdue, .habits, .focus, .next], now: now)
                            .frame(height: 22)
                    }
                }
                .padding(16)
                .environment(\.palette, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 420, height: 180), scheme: scheme, name: "menubar-labels-\(suffix)"
            )
        }
    }

    /// `titled` 为 true 时使用带标题栏的真实窗口，并让 SwiftUI 接管工具栏与标题，截图包含工具栏。
    /// README 用的截图（示例数据）：任务、习惯与菜单栏面板，浅色与深色各一张。
    /// 生成后复制到 `assets/`：`cp …/deadliner-snapshots/readme-*.png assets/`。
    func testRenderReadmeScreenshots() throws {
        func habit(_ id: String, _ name: String, done: Int, target: Int, quantity: Bool = false, completed: Bool = false,
                   category: String? = nil) -> HabitItem {
            HabitItem(id: id, name: name, note: "", colorHex: nil, categoryId: category, doneCount: done, targetCount: target,
                      isCompleted: completed, canApplyPrimaryAction: true, actionKind: quantity ? .addQuantity : .checkOff,
                      actionAmount: quantity ? 250 : 1, unit: quantity ? "ml" : nil, goalWindow: .scheduledDay,
                      scheduleKind: .weeklyDays, weekdaysMask: nil, isDue: true, dueReason: "DUE", hintKind: nil, daysUntil: nil)
        }
        let calendar = Calendar.current
        let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let week = (0..<7).map { offset -> HabitDay in
            let date = HabitDates.string(calendar.date(byAdding: .day, value: offset, to: monday)!)
            return HabitDay(date: date, completed: offset % 3, total: 3, fraction: Double(offset % 3) / 3)
        }
        let habits = [habit("1", "示例习惯 A", done: 1, target: 1, completed: true, category: "c2"),
                      habit("2", "示例习惯 B", done: 500, target: 2000, quantity: true),
                      habit("3", "示例习惯 C", done: 0, target: 1, category: "c3")]
        let now = self.now
        let focusDays = (0..<7).map { FocusStore.DayPoint(date: HabitDates.string(now.addingTimeInterval(Double($0 - 6) * 86400)), seconds: [1800, 5400, 0, 7200, 3600, 9000, 2400][$0]) }
        let summary = MenuBarSummary.make(tasks: sampleTasks, habits: Array(habits.prefix(2)),
                                          today: HabitDay(date: "x", completed: 1, total: 2, fraction: 0.5),
                                          focusTodaySeconds: 4800, focusDays: focusDays, now: now, focusWeekSeconds: 21600)

        for (scheme, tokens) in [(ColorScheme.light, DeadlinerPalette.light), (ColorScheme.dark, DeadlinerPalette.dark)] {
            let suffix = scheme == .dark ? "dark" : "light"
            func page<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> Content) -> some View {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(tokens.onSurfaceVariant)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    content()
                }
                .background(tokens.pageBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .padding(36)
                .background(LinearGradient(colors: [Color(hex: 0x6D83F2), Color(hex: 0xC084FC)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .environment(\.palette, tokens).environment(\.colorScheme, scheme).environment(\.forceLegacyGlass, true)
            }
            try capture(page("任务", "\(sampleTasks.count) 个任务") {
                TaskListContent(tasks: TaskListStore.sorted(sampleTasks, by: .dueDate), totalCount: sampleTasks.count,
                                categories: sampleCategories, isLoading: false, errorMessage: nil, now: now, layout: .double)
            }, size: NSSize(width: 1180, height: 520), scheme: scheme, name: "readme-tasks-\(suffix)")
            try capture(page("习惯", "今天 1/3") {
                HabitsContent(daily: habits, period: [], upcoming: [], week: week, selectedDate: week[4].date,
                              categories: sampleCategories, isLoading: false, errorMessage: nil, searchText: "")
            }, size: NSSize(width: 1000, height: 640), scheme: scheme, name: "readme-habits-\(suffix)")
            try capture(
                MenuBarPanelContent(summary: summary, style: .dashboard, sections: PanelSection.defaults, syncStatus: .succeeded(now), now: now)
                    .padding(36)
                    .background(LinearGradient(colors: [Color(hex: 0x6D83F2), Color(hex: 0xC084FC)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .environment(\.palette, tokens).environment(\.colorScheme, scheme).environment(\.forceLegacyGlass, true),
                size: NSSize(width: 450, height: 860), scheme: scheme, name: "readme-menubar-\(suffix)"
            )
        }
    }

    private func capture<V: View>(_ view: V, size: NSSize, scheme: ColorScheme, name: String, titled: Bool = false) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let style: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let window = NSWindow(contentRect: hosting.frame, styleMask: style, backing: .buffered, defer: false)
        if titled {
            hosting.sceneBridgingOptions = .all
            window.toolbarStyle = .unified
        }
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(titled ? 1.2 : 0.5))
        hosting.layoutSubtreeIfNeeded()
        // 带标题栏时截取整个窗口框架（含工具栏），否则只截内容。
        let target: NSView = titled ? (window.contentView?.superview ?? hosting) : hosting
        let rep = try XCTUnwrap(target.bitmapImageRepForCachingDisplay(in: target.bounds))
        target.cacheDisplay(in: target.bounds, to: rep)
        window.orderOut(nil)
        let url = directory.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SNAPSHOT \(url.path)")
    }

    private var sampleCategories: [String: CategoryItem] {
        [
            "c1": CategoryItem(id: "c1", name: "工作", iconKey: "briefcase", colorHex: "#4A90E2", sortOrder: 0),
            "c2": CategoryItem(id: "c2", name: "学习", iconKey: "book", colorHex: "#7ED321", sortOrder: 1),
            "c3": CategoryItem(id: "c3", name: "生活", iconKey: "home", colorHex: "#F5A623", sortOrder: 2),
        ]
    }

    private var sampleTasks: [TaskItem] {
        func make(_ id: String, _ title: String, note: String = "", due: TimeInterval?, start: TimeInterval? = nil,
                  state: TaskItem.State = .active, starred: Bool = false, category: String? = nil, sub: (Int, Int) = (0, 0)) -> TaskItem {
            TaskItem(id: id, title: title, note: note, startAt: start.map { now.addingTimeInterval($0) },
                     dueAt: due.map { now.addingTimeInterval($0) }, state: state, isStarred: starred, categoryId: category,
                     subtaskDone: sub.0, subtaskTotal: sub.1, createdAt: now.addingTimeInterval(-86400 * 6), updatedAt: nil)
        }
        return [
            make("1", "示例任务 A", note: "示例备注", due: 86400 * 3, starred: true, category: "c1", sub: (1, 3)),
            make("2", "示例任务 B", due: 3600 * 5, category: "c2"),
            make("3", "示例任务 C", note: "这是一段比较长的示例备注，用来检查单行截断是否正常", due: -3600 * 26, category: "c3"),
            make("4", "示例任务 D", due: 86400 * 12, start: 86400 * 2),
            make("5", "示例任务 E：标题很长很长很长很长很长很长很长很长很长", due: 86400 * 1.5, category: "c1", sub: (2, 2)),
            make("6", "示例任务 F", due: nil),
            make("7", "示例任务 G", due: -86400, state: .completed, category: "c2"),
            make("8", "示例任务 H", due: 86400, state: .abandoned),
        ]
    }
}
