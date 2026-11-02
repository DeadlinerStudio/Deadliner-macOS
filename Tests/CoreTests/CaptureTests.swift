import SwiftUI
import XCTest
import Shared
@testable import DeadlinerTestHost

/// 灵感：经过 Core 的 CaptureRepository 读写；合并规则与 Core CaptureViewModel 相同。
@MainActor
final class CaptureTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!
    private var store: CaptureStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-capture-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
                                     deviceId: "macos-test-device")
        store = CaptureStore(database: container.database)
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testCreateEditMergeConsumeAndDelete() async throws {
        XCTAssertNil(store.create("   "))
        let first = try XCTUnwrap(store.create("  示例灵感一  "))
        try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        let second = try XCTUnwrap(store.create("示例灵感二"))
        XCTAssertEqual(store.items.map(\.id), [second, first])  // 新的在前
        XCTAssertEqual(store.items.last?.text, "示例灵感一")

        store.update(first, text: "示例灵感一（改）")
        XCTAssertEqual(store.items.first { $0.id == first }?.text, "示例灵感一（改）")

        let merged = try XCTUnwrap(store.merge([first, second]))
        XCTAssertEqual(merged.text, "示例灵感一（改）\n\n---\n\n示例灵感二")  // 按创建时间，与 Core 相同的分隔符
        XCTAssertEqual(store.items.map(\.id), [merged.id])
        XCTAssertNil(container.database.captures.listUnconsumed().first { $0.uid == first && !$0.isDeleted })

        store.markConsumed(merged.id)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(container.database.captures.find(uid: merged.id)?.isConsumed, true)

        let third = try XCTUnwrap(store.create("示例灵感三"))
        store.searchText = "三"
        XCTAssertEqual(store.visibleItems.map(\.id), [third])
        store.delete([third])
        XCTAssertTrue(store.items.isEmpty)
    }

    func testTitleAndNote() {
        XCTAssertEqual(CaptureStore.titleAndNote("开始每周复盘\n周日晚上 20:00\n准备模板").title, "开始每周复盘")
        XCTAssertEqual(CaptureStore.titleAndNote("开始每周复盘\n周日晚上 20:00\n准备模板").note, "周日晚上 20:00\n准备模板")
        XCTAssertEqual(CaptureStore.titleAndNote("\n\n只有一行").title, "只有一行")
        let long = String(repeating: "长", count: 70)
        XCTAssertEqual(CaptureStore.titleAndNote(long).title.count, 60)
        XCTAssertEqual(CaptureStore.titleAndNote(long).note.count, 10)
    }

    func testRenderCapturePage() throws {
        struct Host: View {
            let items: [CaptureStore.Idea]
            @State private var draft = ""
            @FocusState private var focused: Bool
            var body: some View {
                CaptureContent(items: items, draft: $draft, composerFocused: $focused, layout: .double)
            }
        }
        let now = Date()
        let items = [
            CaptureStore.Idea(id: "1", text: "示例灵感：也许可以开始每周复盘", createdAt: now.addingTimeInterval(-600)),
            CaptureStore.Idea(id: "2", text: "示例灵感：整理书单\n先列出想读的五本", createdAt: now.addingTimeInterval(-7200)),
            CaptureStore.Idea(id: "3", text: "示例灵感：周末去看展", createdAt: now.addingTimeInterval(-86400 * 2)),
        ]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("deadliner-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let hosting = NSHostingView(rootView: Host(items: items).deadlinerTheme().environment(\.colorScheme, scheme))
            hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 560)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.backgroundColor = .windowBackgroundColor
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderBack(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            hosting.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            window.orderOut(nil)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("capture-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}
