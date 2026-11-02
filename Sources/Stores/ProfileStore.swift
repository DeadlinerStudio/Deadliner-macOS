import AppKit
import Foundation
import Observation
import Shared

/// 个人资料：昵称经 Core 的 `UserProfileRepository` 同步到各端；头像图片只保存在本机
/// （Core 只同步文件名，与 Android / iOS 相同），其他设备没有这张图时显示首字母。
@MainActor
@Observable
final class ProfileStore {
    private(set) var nickname = ""
    private(set) var avatar: NSImage?

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private let avatarDirectory: () throws -> URL

    init(database: DeadlinerDatabase, avatarDirectory: @escaping () throws -> URL = ProfileStore.defaultAvatarDirectory) {
        self.database = database
        self.avatarDirectory = avatarDirectory
    }

    nonisolated static func defaultAvatarDirectory() throws -> URL {
        let directory = try AppPaths.applicationSupportDirectory().appendingPathComponent("avatars", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 显示用的名字：没有昵称时为「Deadliner」。
    var displayName: String { nickname.isEmpty ? "Deadliner" : nickname }

    /// 头像上的字：昵称的第一个字，没有昵称时为「D」。
    var initial: String { nickname.first.map { String($0).uppercased() } ?? "D" }

    func refresh() {
        let profile = current
        nickname = profile?.nickname ?? ""
        if let name = profile?.avatarFileName, let url = try? avatarDirectory().appendingPathComponent(name) {
            avatar = NSImage(contentsOf: url)
        } else {
            avatar = nil
        }
    }

    func setNickname(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        save { $0.doCopy(uid: $0.uid, nickname: trimmed, avatarFileName: $0.avatarFileName, tier: $0.tier,
                         createdAt: $0.createdAt, updatedAt: CoreClock.now(), isDeleted: false) }
    }

    /// 把图片缩到 256 像素，保存为 PNG，文件名写进资料。
    func setAvatar(from url: URL) throws {
        guard let image = NSImage(contentsOf: url) else { throw ProfileError.unreadableImage }
        let size = NSSize(width: 256, height: 256)
        let resized = NSImage(size: size)
        resized.lockFocus()
        let side = min(image.size.width, image.size.height)
        let source = NSRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        image.draw(in: NSRect(origin: .zero, size: size), from: source, operation: .copy, fraction: 1)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { throw ProfileError.unreadableImage }
        let name = "avatar-\(UUID().uuidString.lowercased()).png"
        try png.write(to: try avatarDirectory().appendingPathComponent(name), options: .atomic)
        save { $0.doCopy(uid: $0.uid, nickname: $0.nickname, avatarFileName: name, tier: $0.tier,
                         createdAt: $0.createdAt, updatedAt: CoreClock.now(), isDeleted: false) }
    }

    func removeAvatar() {
        save { $0.doCopy(uid: $0.uid, nickname: $0.nickname, avatarFileName: nil, tier: $0.tier,
                         createdAt: $0.createdAt, updatedAt: CoreClock.now(), isDeleted: false) }
    }

    enum ProfileError: LocalizedError {
        case unreadableImage
        var errorDescription: String? { "无法读取这张图片" }
    }

    /// 第一份未删除的资料（各端共用一份）。
    private var current: UserProfile? {
        database.profiles.list().filter { !$0.isDeleted }.sorted { $0.createdAt < $1.createdAt }.first
    }

    private func save(_ change: (UserProfile) -> UserProfile) {
        if let existing = current {
            database.profiles.update(profile: change(existing))
        } else {
            let now = CoreClock.now()
            let blank = UserProfile(uid: PlatformIdentity.shared.doNewId(), nickname: "", avatarFileName: nil, tier: UserTier.free,
                                    createdAt: now, updatedAt: now, isDeleted: false)
            database.profiles.create(profile: change(blank))
        }
        refresh()
    }
}
