import Foundation
import Shared

/// 应用唯一的 Core 容器（对应 Core iOS 迁移指南中的 composition root）。
///
/// 数据库、同步与业务规则全部由 DeadlinerCore 负责；这里只决定数据库放在哪里、
/// 本机设备 ID 是什么，并在应用生命周期结束时关闭数据库。
@MainActor
final class MacCoreContainer {
    /// Core 固定使用的数据库文件名，与旧版 Mac 数据完全隔离。
    static let databaseFileName = "deadliner_new_era.db"

    let database: DeadlinerDatabase
    let databaseURL: URL

    init(databaseURL: URL, deviceId: String) {
        self.databaseURL = databaseURL
        let factory = MacosDatabaseDriverFactory(databasePath: databaseURL.path, deviceId: deviceId)
        database = DeadlinerDatabase.companion.create(factory: factory)
    }

    /// 正式运行时的容器：数据库放在本应用的 Application Support 目录下。
    static func makeDefault() throws -> MacCoreContainer {
        let directory = try AppPaths.applicationSupportDirectory()
        return MacCoreContainer(
            databaseURL: directory.appendingPathComponent(databaseFileName),
            deviceId: DeviceIdentity.current()
        )
    }

    /// 链接进来的 Core 版本，例如 `DeadlinerCore-xxxxxx-mac/apple-bridges@…`。
    static var coreVersion: String { DeadlinerCoreVersion.shared.value }

    func close() {
        database.close()
    }
}
