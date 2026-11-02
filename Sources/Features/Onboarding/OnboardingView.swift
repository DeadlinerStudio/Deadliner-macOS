import SwiftUI

/// 首次启动的引导：欢迎、连接手机、通知、菜单栏、完成。
/// 设置 → 关于中可以重新打开。
enum Onboarding {
    static let doneKey = "onboarding.done"
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, sync, notifications, menuBar, done
    }

    /// 打开同步设置（关闭引导后跳转）。
    var openSyncSettings: () -> Void
    /// 通知开关变化后重新计算提醒。
    var notificationsChanged: () -> Void
    var finish: () -> Void

    @State private var step: Step = .welcome
    @State private var notificationsDenied = false
    @AppStorage(NotificationSettings.enabledKey) private var notificationsEnabled = false
    @AppStorage(MenuBarSettings.enabledKey) private var menuBarEnabled = true
    @AppStorage(MenuBarSettings.styleKey) private var statusStyleRaw = StatusItemStyle.iconCount.rawValue
    @Environment(\.palette) private var t

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? t.primary : t.onSurface.opacity(0.12))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            Group {
                switch step {
                case .welcome: welcome
                case .sync: sync
                case .notifications: notifications
                case .menuBar: menuBar
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)

            HStack {
                if step != .welcome && step != .done {
                    Button("上一步") { move(-1) }
                }
                Spacer()
                if step != .done {
                    Button("跳过引导", action: finish).buttonStyle(.borderless)
                }
                Button(step == .done ? "开始使用" : "下一步") { step == .done ? finish() : move(1) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 560, height: 440)
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func page<Content: View>(_ icon: String, _ title: String, _ text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 34, weight: .medium)).foregroundStyle(t.primary)
            Text(title).font(.title2.weight(.bold))
            Text(text).font(.body).foregroundStyle(t.onSurfaceVariant).fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private var welcome: some View {
        page("calendar.badge.clock", "欢迎使用 Deadliner",
             "管理截止时间、习惯和灵感。Mac 版与手机共用同一套数据和规则，通过 WebDAV 与手机双向同步。") {
            VStack(alignment: .leading, spacing: 8) {
                Label("任务：截止时间、子任务、分类，单列 / 多列显示", systemImage: "checklist")
                Label("习惯：打卡、计量、艾宾浩斯复习", systemImage: "target")
                Label("概览：任意时间范围的统计与趋势", systemImage: "chart.bar.xaxis")
                Label("菜单栏：随时看今天要做的事", systemImage: "menubar.rectangle")
            }
            .font(.callout)
            .padding(.top, 6)
        }
    }

    private var sync: some View {
        page("arrow.triangle.2.circlepath", "连接手机",
             "第一次打开时这里没有数据。填写与手机相同的 WebDAV 服务器地址、用户名和应用密码后，会先备份云端文件，再双向同步。") {
            HStack {
                Button("现在设置同步") {
                    finish()
                    openSyncSettings()
                }
                .buttonStyle(.bordered)
                Text("也可以稍后在 设置 → WebDAV 同步 中设置。").font(.caption).foregroundStyle(t.onSurfaceVariant)
            }
            .padding(.top, 6)
        }
    }

    private var notifications: some View {
        page("bell.badge", "开启提醒", "任务到期前一天、到期时以及习惯打卡时提醒你，提醒时间与手机一致。") {
            Toggle("开启通知", isOn: Binding(get: { notificationsEnabled }, set: { enable($0) }))
                .toggleStyle(.switch)
                .padding(.top, 6)
            if notificationsDenied {
                Text("系统设置中没有允许 Deadliner 发送通知，可以在「系统设置 → 通知」中打开。")
                    .font(.caption).foregroundStyle(t.error)
            }
        }
    }

    private var menuBar: some View {
        page("menubar.rectangle", "菜单栏", "在菜单栏查看今天到期、逾期和习惯进度，点击打开面板。样式和面板内容都可以在设置中调整。") {
            Toggle("在菜单栏显示 Deadliner", isOn: $menuBarEnabled).toggleStyle(.switch).padding(.top, 6)
            if menuBarEnabled {
                Picker("样式", selection: $statusStyleRaw) {
                    ForEach(StatusItemStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .frame(maxWidth: 280)
            }
        }
    }

    private var done: some View {
        page("checkmark.seal", "准备好了", "按 ⌘N 新建任务，⌘F 搜索，⌘R 立即同步。这份引导可以在 设置 → 关于 中再次打开。") {}
    }

    private func enable(_ on: Bool) {
        guard on else {
            notificationsEnabled = false
            notificationsChanged()
            return
        }
        _Concurrency.Task {
            let granted = await NotificationController.requestAuthorization()
            notificationsDenied = !granted
            notificationsEnabled = granted
            notificationsChanged()
        }
    }
}

/// 编辑个人资料：昵称（同步）与头像（本机）。
struct ProfileSheet: View {
    let store: ProfileStore
    var onClose: () -> Void
    @State private var nickname: String
    @State private var errorMessage: String?
    @Environment(\.palette) private var t

    init(store: ProfileStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _nickname = State(initialValue: store.nickname)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("个人资料").font(.headline)
            HStack(spacing: 16) {
                ProfileAvatar(store: store, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Button("选择头像…") { chooseAvatar() }
                    if store.avatar != nil {
                        Button("移除头像", role: .destructive) { store.removeAvatar() }.buttonStyle(.borderless)
                    }
                }
            }
            TextField("昵称", text: $nickname, prompt: Text("昵称"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            Text("昵称会同步到其他设备；头像只保存在这台 Mac 上。")
                .font(.caption).foregroundStyle(t.onSurfaceVariant)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(t.error)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: onClose).keyboardShortcut(.cancelAction)
                Button("保存") {
                    store.setNickname(nickname)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.setAvatar(from: url) } catch { errorMessage = error.localizedDescription }
    }
}

/// 圆形头像：有图片时显示图片，否则显示昵称首字。
struct ProfileAvatar: View {
    let store: ProfileStore
    var size: CGFloat = 28
    @Environment(\.palette) private var t

    var body: some View {
        Group {
            if let avatar = store.avatar {
                Image(nsImage: avatar).resizable().scaledToFill()
            } else {
                Text(store.initial)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(t.primary.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
