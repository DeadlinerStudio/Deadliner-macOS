# Deadliner for macOS

SwiftUI 原生 Mac 客户端。数据库、同步和业务规则全部由 [DeadlinerCore](../upstream-latest/deadliner-core)（byos 分支）负责，本工程只做界面和系统集成。规范见 [项目规范_Mac端基于Core重写.md](../项目规范_Mac端基于Core重写.md)。

## 环境

- Apple Silicon Mac，macOS 14 及以上
- Xcode 27.2（需完成 `sudo xcodebuild -runFirstLaunch`）
- JDK 21（Zulu）
- XcodeGen（`brew install xcodegen`）

## 构建

```bash
scripts/build-core.sh debug      # 构建 Core，部署到 Frameworks/Shared.framework
xcodegen generate                # 由 project.yml 生成 DeadlinerMac.xcodeproj
xcodebuild -project DeadlinerMac.xcodeproj -scheme DeadlinerMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
```

在 Xcode 里构建时，第一步会自动运行 `scripts/build-core.sh`，避免打进旧版本的 Core。

## Core 的接入方式

- Core 位置默认为 `../upstream-latest/deadliner-core`，可以用 `DEADLINER_CORE_DIR` 指定。
- Lifi（闭源 AI）使用 Core 官方的公开回退 `-PlifiMode=stub`，AI 功能不可用。
- `scripts/deadliner-mac.init.gradle` 在构建时为 Core 加上 macOS framework 导出，不修改 Core 的文件。
- 页面状态使用 Core `appleMain` 中的 `Ios*StateBridge`。这 4 个类是在本地分支 `mac/apple-bridges` 上从 `iosMain` 原样移过来的，类名不变，iOS 头文件逐字节一致。

## 数据

- 启用了 App Sandbox。数据库位于 `~/Library/Containers/com.deadliner.macos/Data/Library/Application Support/com.deadliner.macos/deadliner_new_era.db`。
- 与旧版 Electron 应用的数据完全隔离。
