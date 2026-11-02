import AppKit
import XCTest
import Shared
@testable import DeadlinerTestHost

/// 个人资料：昵称经 Core 同步；头像保存在本机（测试使用临时目录）。
@MainActor
final class ProfileTests: XCTestCase {
    private var directory: URL!
    private var container: MacCoreContainer!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadliner-profile-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = MacCoreContainer(databaseURL: directory.appendingPathComponent(MacCoreContainer.databaseFileName),
                                     deviceId: "macos-test-device")
    }

    override func tearDown() async throws {
        container?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testNicknameAndAvatar() throws {
        let avatars = directory.appendingPathComponent("avatars", isDirectory: true)
        try FileManager.default.createDirectory(at: avatars, withIntermediateDirectories: true)
        let store = ProfileStore(database: container.database, avatarDirectory: { avatars })
        store.refresh()
        XCTAssertEqual(store.displayName, "Deadliner")
        XCTAssertEqual(store.initial, "D")

        store.setNickname("  示例昵称  ")
        XCTAssertEqual(store.nickname, "示例昵称")
        XCTAssertEqual(store.initial, "示")
        XCTAssertEqual(container.database.profiles.list().filter { !$0.isDeleted }.count, 1)
        store.setNickname("示例昵称二")
        XCTAssertEqual(container.database.profiles.list().filter { !$0.isDeleted }.count, 1)  // 只更新同一份资料

        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 40, height: 20).fill(); image.unlockFocus()
        let source = directory.appendingPathComponent("source.png")
        try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: source)
        try store.setAvatar(from: source)
        XCTAssertNotNil(store.avatar)
        let name = try XCTUnwrap(container.database.profiles.list().first?.avatarFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: avatars.appendingPathComponent(name).path))
        store.removeAvatar()
        XCTAssertNil(store.avatar)
        XCTAssertEqual(store.nickname, "示例昵称二")
    }

    func testGreeting() {
        let calendar = Calendar.current
        func at(_ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour))! }
        XCTAssertEqual(Sidebar.greeting(at(7)), "早上好")
        XCTAssertEqual(Sidebar.greeting(at(15)), "下午好")
        XCTAssertEqual(Sidebar.greeting(at(2)), "夜深了，早点休息")
    }
}
