import XCTest
import SwiftUI
@testable import Deadliner_for_macOS

/// 用占位数据渲染任务页截图（浅色 / 深色），供人工对照手机界面。
/// 截图保存在测试进程临时目录下的 `deadliner-snapshots/`，路径会打印到测试日志。
@MainActor
final class TaskListSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRenderTaskListLightAndDark() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, tokens, scheme) in [("tasks-light", MiuixTokens.light, ColorScheme.light), ("tasks-dark", MiuixTokens.dark, ColorScheme.dark)] {
            let view = TaskListContent(
                tasks: TaskListStore.sorted(sampleTasks, by: .dueDate),
                totalCount: sampleTasks.count,
                categories: sampleCategories,
                isLoading: false,
                errorMessage: nil,
                searchText: .constant(""),
                sortOrder: .constant(.dueDate),
                now: now
            )
            .environment(\.miuix, tokens)
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
        for (scheme, tokens) in [(ColorScheme.light, MiuixTokens.light), (ColorScheme.dark, MiuixTokens.dark)] {
            let suffix = scheme == .dark ? "dark" : "light"
            try capture(
                TaskEditorSheet(commands: commands, categoryCommands: categoryCommands, draft: draft) {}
                    .environment(\.miuix, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 520, height: 660), scheme: scheme, name: "editor-\(suffix)"
            )
            try capture(
                CategoryManagerSheet(commands: categoryCommands) {}
                    .environment(\.miuix, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 480, height: 560), scheme: scheme, name: "categories-\(suffix)"
            )
        }
    }

    /// 习惯页、存档页与带侧栏的整体布局截图（占位数据）。
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
            searchText: .constant("")
        )
        let archiveView = ArchiveContent(
            tasks: Array(sampleTasks.prefix(2)).map { var task = $0; task.state = .archived; return task },
            habits: [.init(id: "h", name: "示例习惯 F", colorHex: "#10B981", categoryId: nil)],
            categories: sampleCategories
        )
        for (scheme, tokens) in [(ColorScheme.light, MiuixTokens.light), (ColorScheme.dark, MiuixTokens.dark)] {
            let suffix = scheme == .dark ? "dark" : "light"
            try capture(
                HStack(spacing: 0) { Sidebar(page: .constant(.habits)); habitsView }
                    .environment(\.miuix, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 1240, height: 680), scheme: scheme, name: "habits-\(suffix)"
            )
            try capture(
                archiveView.environment(\.miuix, tokens).environment(\.colorScheme, scheme),
                size: NSSize(width: 1000, height: 480), scheme: scheme, name: "archive-\(suffix)"
            )
        }
    }

    private func capture<V: View>(_ view: V, size: NSSize, scheme: ColorScheme, name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
