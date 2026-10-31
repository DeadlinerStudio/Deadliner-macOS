import Foundation
import Security

/// WebDAV 同步设置。地址、用户名、开关存 UserDefaults；应用密码只存钥匙串，不写数据库、不打印到日志。
struct SyncSettings: Equatable {
    var serverURL: String
    var username: String
    var enabled: Bool

    private static let urlKey = "sync.webdav.url"
    private static let userKey = "sync.webdav.username"
    private static let enabledKey = "sync.webdav.enabled"

    static func load(from defaults: UserDefaults = .standard) -> SyncSettings {
        SyncSettings(
            serverURL: defaults.string(forKey: urlKey) ?? "",
            username: defaults.string(forKey: userKey) ?? "",
            enabled: defaults.bool(forKey: enabledKey)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(serverURL, forKey: Self.urlKey)
        defaults.set(username, forKey: Self.userKey)
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    /// 规范化后的服务器地址：去掉首尾空白，补上结尾的 `/`。
    var normalizedURL: String {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
    }

    /// 交给 Core 之前的检查：Core 的 WebDavSyncTransport 要求地址以 http(s):// 开头，否则直接抛异常。
    var validationError: String? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "请填写服务器地址" }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            return "服务器地址需要以 https:// 开头"
        }
        if username.trimmingCharacters(in: .whitespaces).isEmpty { return "请填写用户名" }
        return nil
    }

    var usesHTTPS: Bool { serverURL.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("https://") }
}

/// 钥匙串中的 WebDAV 应用密码（通用密码项，按服务器地址 + 用户名区分）。
struct KeychainPasswordStore {
    var service = "com.deadliner.macos.webdav"

    func password(url: String, username: String) -> String? {
        var query = baseQuery(url: url, username: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func setPassword(_ password: String, url: String, username: String) -> Bool {
        let query = baseQuery(url: url, username: username)
        let data = Data(password.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func deletePassword(url: String, username: String) {
        SecItemDelete(baseQuery(url: url, username: username) as CFDictionary)
    }

    private func baseQuery(url: String, username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(username)@\(url)",
        ]
    }
}
