import Foundation

/// 本应用的数据目录。启用 App Sandbox 后，实际位置在
/// `~/Library/Containers/com.deadliner.macos/Data/Library/Application Support/`。
enum AppPaths {
    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.deadliner.macos", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// 本机设备 ID：第一次启动时生成，之后保持不变；Core 用它参与同步版本号的比较。
enum DeviceIdentity {
    private static let key = "deadliner.deviceId"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = "macos-" + UUID().uuidString.lowercased()
        defaults.set(created, forKey: key)
        return created
    }
}

import AppKit

/// 应用图标：直接读取包内的 AppIcon.icns，不依赖 LaunchServices 是否已登记本应用。
enum AppIconImage {
    @MainActor static let image: NSImage = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage
}
