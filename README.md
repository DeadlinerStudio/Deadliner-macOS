# Deadliner for macOS

Deadliner，一款简洁高效的 Deadline 记录管理软件。这是它的 macOS 原生客户端，基于 SwiftUI 开发，与手机端共用 [DeadlinerCore](https://github.com/DeadlinerStudio/DeadlinerCore)：数据库、同步和业务规则都由 Core 负责，与 Android、iOS、鸿蒙端保持一致。

### 相关项目

- [**DeadlinerCore**](https://github.com/DeadlinerStudio/DeadlinerCore)：Deadliner 跨平台核心（Kotlin Multiplatform），各端共用的数据、同步与业务规则
- [**Deadliner**](https://github.com/DeadlinerStudio/Deadliner)：**Android** 客户端
- [**Deadliner-iOS**](https://github.com/DeadlinerStudio/Deadliner-iOS)：基于 SwiftUI 开发的 **iOS** 客户端
- [**DeadlinerNEXT**](https://github.com/DeadlinerStudio/DeadlinerNEXT)：基于 ArkTS 开发的**原生鸿蒙**客户端
- [**Deadliner-Client**](https://github.com/DeadlinerStudio/Deadliner-Client)：基于 Electron + React 的旧版桌面客户端

## 下载

**[下载最新版本（DMG）](../../releases/latest)**：适用于 Apple Silicon Mac，macOS 14 及以上。

1. 打开下载的 `Deadliner-for-macOS-<版本>-arm64.dmg`，把 **Deadliner for macOS** 拖进「应用程序」文件夹。
2. 应用目前没有经过 Apple 公证，第一次打开会提示「无法验证开发者」。先关掉提示，到 **系统设置 → 隐私与安全性**，在下方点 **仍要打开**，输入密码确认。每台 Mac 只需要放行一次。

Liquid Glass 与侧栏下的顶部浮光需要 macOS 26；更早的系统使用毛玻璃效果，功能相同。

## 功能

- **任务**：新建、编辑、完成、放弃、归档、删除、标星、延期；子任务与分类
- **列表**：单列 / 双列 / 三列；搜索（含归档中的匹配）、按分类筛选、排序
- **多选操作**：工具栏「选择」或按住 ⌘ 点按卡片，批量完成、归档、删除
- **习惯**：今日完成度、一周日期条、打卡（勾选型 / 计量型）、艾宾浩斯复习
- **概览**：总览（全部时间或任选一个月）与趋势（周 / 月 / 年）、活跃热力图、月度回顾
- **专注**：查看各设备同步过来的专注记录与统计
- **归档**：搜索、取消归档、恢复与删除
- **WebDAV 同步**：与手机端使用同一个同步文件，双向同步；后台同步间隔可选
- **通知**：任务到期前一天、到期时与习惯打卡提醒，提醒时间与手机端一致
- **备份**：导出 / 导入与手机端同一格式的完整备份
- **菜单栏**：四种显示样式，面板内查看今日任务、习惯与专注，内容可自定义
- **外观**：浅色 / 深色 / 跟随系统、15 种主题色、顶部浮光、衬线字体

## 技术栈

- **Swift 6** / **SwiftUI**，macOS 14+，Apple Silicon
- **DeadlinerCore**（Kotlin Multiplatform）：以 macOS framework 链接，提供数据库、同步、通知计划与统计
- **Swift Charts**：概览图表
- **UserNotifications**、**Security（钥匙串）**、**Network**
- **XcodeGen**：由 `project.yml` 生成 Xcode 工程

## 使用说明

1. 第一次打开时数据库为空。到 **设置 → WebDAV 同步** 填写与手机端相同的服务器地址、用户名和应用密码，点「检测服务器」确认后启用。
2. 启用同步前，应用会先把云端的同步文件备份到本机；云端没有同步文件时会先询问，避免地址填错时新建一份空数据。
3. 点右下角 **+** 或按 ⌘N 新建任务；悬停在卡片上可以完成，右键菜单里有更多操作。
4. 在 **设置 → 通知** 中开启提醒，在 **设置 → 菜单栏** 中自定义菜单栏图标与面板。

快捷键：⌘N 新建任务、⌘F 搜索、⌘R 立即同步、⌘1～⌘6 切换页面、⌘, 设置。

## 从源码构建

需要：Xcode 27.2（完成 `sudo xcodebuild -runFirstLaunch`）、JDK 21、XcodeGen（`brew install xcodegen`），以及一份 DeadlinerCore。

```bash
scripts/build-core.sh debug      # 构建 Core，部署到 Frameworks/Shared.framework
xcodegen generate                # 由 project.yml 生成 DeadlinerMac.xcodeproj
xcodebuild -project DeadlinerMac.xcodeproj -scheme DeadlinerMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
scripts/package.sh ../Deadliner-for-macOS-package   # 打包 DMG 与 ZIP（临时签名，构建目录在 ~/Library/Caches）
```

在 Xcode 里构建时，第一步会自动运行 `scripts/build-core.sh`，避免打进旧版本的 Core。

**Core 的接入方式**

- Core 位置默认为 `../upstream-latest/deadliner-core`，可以用 `DEADLINER_CORE_DIR` 指定。
- 需要包含以下改动的 Core（已向 DeadlinerCore 的 `byos` 分支提交 PR，合并前请使用包含它们的分支）：
  - [#1](https://github.com/DeadlinerStudio/DeadlinerCore/pull/1)：4 个 `Ios*StateBridge` 从 `iosMain` 移到 `appleMain`，供 macOS 使用
  - [#2](https://github.com/DeadlinerStudio/DeadlinerCore/pull/2)：`BackupService.restore` 声明 `@Throws`，导入无效备份时报错而不退出
  - [#3](https://github.com/DeadlinerStudio/DeadlinerCore/pull/3)：防止同步时分类被「未命名分类」覆盖
- Lifi（闭源 AI）使用 Core 官方的公开回退 `-PlifiMode=stub`，AI 功能不可用。
- `scripts/deadliner-mac.init.gradle` 在构建时为 Core 加上 macOS framework 导出，不修改 Core 的文件。
- Core 中用 `require()` 校验的数据（习惯周期、目标、记录方式、WebDAV 地址）在交给 Core 之前先在 Swift 中检查，避免未捕获的 Kotlin 异常导致崩溃。

**测试**：单元测试运行在独立的「Deadliner Test Host」（`com.deadliner.macos.testhost`），与正式应用的设置、钥匙串和数据完全分开，测试中不会连接 WebDAV。

| 目录 | 内容 |
|---|---|
| `Sources/App` | 应用入口、AppModel、侧栏 |
| `Sources/Core` | Core 容器、时间格式、数据目录 |
| `Sources/Stores` | 订阅层（Core 状态 → Swift 值类型）与写入命令 |
| `Sources/Sync` | WebDAV 设置、钥匙串、检测服务器、云端备份、本机备份、同步控制 |
| `Sources/Notifications` | 通知（Core `NotificationGateway` 的 Mac 实现） |
| `Sources/Features` | 各页面与编辑器 |
| `Sources/MenuBar` | 菜单栏项目与面板 |
| `Sources/Theme` | 调色板、主题色、玻璃兼容层、浮光、卡片布局 |

## 数据与隐私

- 启用了 App Sandbox。数据只保存在本机：`~/Library/Containers/com.deadliner.macos/Data/Library/Application Support/com.deadliner.macos/`。
- WebDAV 应用密码只保存在钥匙串，不写入数据库或日志。同步只连接你自己填写的服务器。
- 与旧版 Electron 客户端的数据完全隔离。

## 贡献

欢迎提交 Issue 或 Pull Request。界面文案计划与 iOS 端统一，之后迁移到各端共用的本地化层。
