import AppKit
import CommonCrypto
import CryptoKit
import Foundation
import Shared

/// 与安卓相同的任务分享链接（`DeadlinerURLScheme`，口令派生模式）：
/// `https://www.aritxonly.top/deadliner/share?v=1&k=1&m=pass&s=<salt>&i=<iters>&d=<payload>`，
/// 内容是安卓 `DDLItem` 的 JSON，经 Deflate 压缩、AES-GCM 加密（PBKDF2-HMAC-SHA256 由固定口令派生密钥）。
/// 只用于在设备之间传递一条任务，不经过同步，不改 Core。
enum TaskShareLink {
    static let prefix = "https://www.aritxonly.top/deadliner/share"
    static let legacyPrefix = "deadliner://share"
    private static let passphrase = Array("deadliner-2025".utf8)
    private static let version = 1
    private static let defaultIterations = 200_000

    enum LinkError: LocalizedError, Equatable {
        case notALink, unsupported, corrupted, habit

        var errorDescription: String? {
            switch self {
            case .notALink: "不是 Deadliner 的分享链接"
            case .unsupported: "分享链接的版本不受支持"
            case .corrupted: "分享链接解析错误"
            case .habit: "这是习惯的分享链接，Mac 暂时只能导入任务"
            }
        }
    }

    static func isLink(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix(prefix) || text.hasPrefix(legacyPrefix)
    }

    // MARK: - 安卓 DDLItem（Gson 默认字段名）

    struct Item: Codable, Equatable {
        struct SubTask: Codable, Equatable {
            var id: String
            var content: String
            var isCompleted: Int
            var sortOrder: Int
            var createdAt: String?

            enum CodingKeys: String, CodingKey {
                case id, content
                case isCompleted = "is_completed"
                case sortOrder = "sort_order"
                case createdAt = "created_at"
            }
        }

        var id: Int64 = -1
        var name: String
        var startTime: String
        var endTime: String
        var isCompleted = false
        var state = "ACTIVE"
        var completeTime = ""
        var note: String
        var isArchived = false
        var isStared = false
        var type = "TASK"
        var habitCount = 0
        var habitTotalCount = 0
        var timeStamp: String
        var subTasks: [SubTask] = []

        init(name: String, startTime: String, endTime: String, note: String, isStared: Bool, timeStamp: String, subTasks: [SubTask]) {
            self.name = name
            self.startTime = startTime
            self.endTime = endTime
            self.note = note
            self.isStared = isStared
            self.timeStamp = timeStamp
            self.subTasks = subTasks
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? ""
            endTime = try c.decodeIfPresent(String.self, forKey: .endTime) ?? ""
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            isStared = try c.decodeIfPresent(Bool.self, forKey: .isStared) ?? false
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? "TASK"
            timeStamp = try c.decodeIfPresent(String.self, forKey: .timeStamp) ?? ""
            subTasks = try c.decodeIfPresent([SubTask].self, forKey: .subTasks) ?? []
        }
    }

    // MARK: - 任务 ⇄ 链接

    /// 生成分享链接（只包含名称、时间、备注、星标和子任务；完成状态不带过去，对方导入后是新任务）。
    static func encode(_ draft: TaskDraft, now: Date = Date()) throws -> String {
        let item = Item(
            name: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            startTime: localString(draft.startAt ?? now),
            endTime: draft.dueAt.map { localString($0) } ?? "",
            note: draft.note,
            isStared: draft.isStarred,
            timeStamp: localString(now),
            subTasks: draft.subtasks.enumerated().map { index, sub in
                .init(id: sub.id, content: sub.content, isCompleted: sub.isCompleted ? 1 : 0, sortOrder: index, createdAt: nil)
            }
        )
        let json = try JSONEncoder().encode(item)
        let salt = randomBytes(16)
        let saltB64 = base64url(salt)
        let aad = Data("v=\(version)&k=1&m=pass&s=\(saltB64)&i=\(defaultIterations)".utf8)
        let key = try deriveKey(salt: salt, iterations: defaultIterations)
        let compressed = try (json as NSData).compressed(using: .zlib) as Data
        let sealed = try AES.GCM.seal(compressed, using: key, nonce: AES.GCM.Nonce(data: randomBytes(12)), authenticating: aad)
        var envelope = Data([UInt8(version)])
        envelope.append(contentsOf: sealed.nonce)
        envelope.append(sealed.ciphertext)
        envelope.append(sealed.tag)
        var components = URLComponents(string: prefix)!
        components.queryItems = [
            .init(name: "v", value: "\(version)"), .init(name: "k", value: "1"), .init(name: "m", value: "pass"),
            .init(name: "s", value: saltB64), .init(name: "i", value: "\(defaultIterations)"), .init(name: "d", value: base64url(envelope)),
        ]
        return components.string!
    }

    /// 解析分享链接，得到可以在编辑器中打开的新任务草稿（还没有保存）。
    static func decode(_ link: String) throws -> TaskDraft {
        let item = try decodeItem(link)
        guard item.type.uppercased() != "HABIT" else { throw LinkError.habit }
        var draft = TaskDraft()
        draft.title = item.name
        draft.note = item.note
        draft.startAt = parseLocal(item.startTime)
        draft.dueAt = parseLocal(item.endTime)
        draft.isStarred = item.isStared
        draft.subtasks = item.subTasks.sorted { $0.sortOrder < $1.sortOrder }.map {
            // 新任务的子任务用新的 ID，避免与原设备上的子任务冲突。
            .init(id: PlatformIdentity.shared.doNewId(), content: $0.content, isCompleted: $0.isCompleted != 0)
        }
        return draft
    }

    static func decodeItem(_ link: String) throws -> Item {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLink(text), let components = URLComponents(string: text) else { throw LinkError.notALink }
        func value(_ name: String) -> String? { components.queryItems?.first { $0.name == name }?.value }
        guard let v = value("v").flatMap(Int.init), v == version, value("m") == "pass" else { throw LinkError.unsupported }
        let kid = value("k").flatMap(Int.init) ?? 1
        let iterations = value("i").flatMap(Int.init) ?? defaultIterations
        guard iterations >= 50_000, iterations <= 5_000_000,
              let saltB64 = value("s"), let salt = data(base64url: saltB64),
              let token = value("d"), let envelope = data(base64url: token),
              envelope.count > 1 + 12 + 16, envelope.first == UInt8(version) else { throw LinkError.corrupted }
        let aad = Data("v=\(v)&k=\(kid)&m=pass&s=\(saltB64)&i=\(iterations)".utf8)
        do {
            let key = try deriveKey(salt: salt, iterations: iterations)
            let body = envelope.dropFirst()
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: body.prefix(12)),
                                            ciphertext: body.dropFirst(12).dropLast(16), tag: body.suffix(16))
            let compressed = try AES.GCM.open(box, using: key, authenticating: aad)
            let json = try (compressed as NSData).decompressed(using: .zlib) as Data
            return try JSONDecoder().decode(Item.self, from: json)
        } catch {
            throw LinkError.corrupted
        }
    }

    // MARK: - 剪贴板

    /// 读取剪贴板中的分享链接（用户点菜单时调用，属于用户主动的粘贴）。
    static func fromPasteboard(_ pasteboard: NSPasteboard = .general) -> String? {
        guard let text = pasteboard.string(forType: .string), isLink(text) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 本机刚复制的链接：自动识别时跳过，不会把自己分享出去的任务再导入一次。
    @MainActor static var lastCopied: String?

    static func copy(_ link: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)
    }

    // MARK: - 时间（安卓 LocalDateTime.toString()，无时区）

    static func localString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var text = String(format: "%04d-%02d-%02dT%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
        if let second = c.second, second != 0 { text += String(format: ":%02d", second) }
        return text
    }

    static func parseLocal(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "T")
        guard parts.count == 2 else { return nil }
        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        let time = parts[1].split(separator: ":")
        guard day.count == 3, time.count >= 2, let hour = Int(time[0]), let minute = Int(time[1]) else { return nil }
        let second = time.count > 2 ? Int(Double(time[2]) ?? 0) : 0
        return calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: hour, minute: minute, second: second))
    }

    // MARK: - 加密细节

    private static func deriveKey(salt: Data, iterations: Int) throws -> SymmetricKey {
        var key = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            passphrase.withUnsafeBufferPointer { pass in
                pass.withMemoryRebound(to: Int8.self) { password in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress, password.count,
                                         saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &key, key.count)
                }
            }
        }
        guard status == kCCSuccess else { throw LinkError.corrupted }
        return SymmetricKey(data: key)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64url text: String) -> Data? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        return Data(base64Encoded: base)
    }
}

/// 自动识别剪贴板中的分享链接（与安卓相同）。默认关闭：macOS 15.4 起，应用自己读取剪贴板时系统会询问是否允许。
enum ShareLinkSettings {
    static let detectClipboardKey = "share.detectClipboard"
}
