# Deadliner for macOS

SwiftUI 原生 Mac 客户端。数据库、同步和业务规则全部由 [DeadlinerCore](../upstream-latest/deadliner-core)（byos 分支）负责，本工程只做界面和系统集成。规范见 [项目规范_Mac端基于Core重写.md](../项目规范_Mac端基于Core重写.md)，界面方向见 [界面方法审计_Mac端.md](../界面方法审计_Mac端.md)。

## 功能

- **任务**：列表（单列 / 双列 / 三列，固定不随宽度变化）、搜索、排序；新建、编辑、完成、放弃、归档、删除、标星；子任务；分类管理。
- **习惯**：今日完成度、一周日期条、打卡（勾选型 / 计量型）、新建与编辑。
- **概览**：总览（今日概况、完成时间分布、历史统计）、趋势（热力图、本周、每月、近 4 周）、月度（上月数据汇总、活动分布、完成的任务），数据来自 Core 的 OverviewViewModel。
- **专注**：只读的汇总与记录列表。
- **归档**：归档的任务与习惯，取消归档 / 恢复 / 删除。
- **WebDAV 同步**：与手机共用 `Deadliner/kmp-changelog-v1.json`；钥匙串保存密码；检测服务器；启用前备份云端文件；云端没有同步文件时先询问。
- **通知**：任务到期前一天、到期时、习惯打卡提醒。提醒时间由 Core 计算（`configureNotificationUpdates` + Mac 端的 `NotificationGateway` 实现），同步合并后自动更新。
- **备份**：导出 Core 格式的完整备份（与手机端同一格式）。
- **菜单栏**：图标 / 数量 / 多项数据 / 胶囊四种样式；仪表盘或列表菜单两种面板，模块可选。
- **外观**：系统侧栏与工具栏；15 种主题色；顶部浮光（沉浸 / 幻彩 / 关闭，macOS 26 起延伸到侧栏下方）；Liquid Glass（macOS 26+）与毛玻璃回退；衬线字体；⌘, 打开设置窗口。

快捷键：⌘N 新建任务、⌘F 搜索、⌘R 立即同步、⌘1～⌘6 切换页面、⌘, 设置。

## 环境

- Apple Silicon Mac，macOS 14 及以上（Liquid Glass 与侧栏浮光延伸需要 macOS 26）
- Xcode 27.2（需完成 `sudo xcodebuild -runFirstLaunch`）
- JDK 21（Zulu）
- XcodeGen（`brew install xcodegen`）

## 构建与测试

```bash
scripts/build-core.sh debug      # 构建 Core，部署到 Frameworks/Shared.framework
xcodegen generate                # 由 project.yml 生成 DeadlinerMac.xcodeproj
xcodebuild -project DeadlinerMac.xcodeproj -scheme DeadlinerMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
scripts/package.sh ../Deadliner-for-macOS-package   # Release 打包（临时签名，构建目录在 ~/Library/Caches）
```

在 Xcode 里构建时，第一步会自动运行 `scripts/build-core.sh`，避免打进旧版本的 Core。

**测试宿主**：单元测试运行在独立的「Deadliner Test Host」（`com.deadliner.macos.testhost`，模块 `DeadlinerTestHost`），与正式应用的设置、钥匙串和沙盒数据完全分开；测试中也不会连接 WebDAV。截图保存在 `~/Library/Containers/com.deadliner.macos.testhost/Data/tmp/deadliner-snapshots/`。Liquid Glass、系统侧栏与工具栏的半透明效果无法离屏截取，需要在真实窗口中检查。

## 目录

| 目录 | 内容 |
|---|---|
| `Sources/App` | 应用入口、AppModel、侧栏 |
| `Sources/Core` | Core 容器、时间格式、数据目录 |
| `Sources/Stores` | 订阅层（Core 状态 → Swift 值类型）与写入命令 |
| `Sources/Sync` | WebDAV 设置、钥匙串、检测服务器、云端备份、同步控制 |
| `Sources/Features` | 各页面与编辑器 |
| `Sources/MenuBar` | 菜单栏项目与面板 |
| `Sources/Theme` | 调色板、主题色、玻璃兼容层、浮光、卡片布局 |

## Core 的接入方式

- Core 位置默认为 `../upstream-latest/deadliner-core`，可以用 `DEADLINER_CORE_DIR` 指定。
- Lifi（闭源 AI）使用 Core 官方的公开回退 `-PlifiMode=stub`，AI 功能不可用。
- `scripts/deadliner-mac.init.gradle` 在构建时为 Core 加上 macOS framework 导出，不修改 Core 的文件。
- 页面状态使用 Core `appleMain` 中的 `Ios*StateBridge`。这 4 个类是在本地分支 `mac/apple-bridges` 上从 `iosMain` 原样移过来的，类名不变，iOS 头文件逐字节一致（计划作为 PR 提交给 Core）。
- Core 中用 `require()` 校验的数据（习惯周期、目标、记录方式、WebDAV 地址）在交给 Core 之前先在 Swift 中检查，避免未捕获的 Kotlin 异常导致崩溃。

## 数据

- 启用了 App Sandbox。数据库位于 `~/Library/Containers/com.deadliner.macos/Data/Library/Application Support/com.deadliner.macos/deadliner_new_era.db`，云端备份在同目录的 `cloud-backups/`。
- 与旧版 Electron 应用的数据完全隔离。
