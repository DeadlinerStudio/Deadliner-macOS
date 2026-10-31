import SwiftUI

/// 外观设置（存 UserDefaults）。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 设置页（MIUIX 分组列表）：WebDAV 同步、外观、关于。
struct SettingsView: View {
    let sync: SyncController
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @Environment(\.palette) private var t

    @State private var form = SyncSettings(serverURL: "", username: "", enabled: false)
    @State private var password = ""
    @State private var message: String?
    @State private var checks: [WebDavProbe.Check] = []
    @State private var probing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(t.onSurface)
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    serverGroup
                    if !checks.isEmpty { probeGroup }
                    statusGroup
                    appearanceGroup
                    aboutGroup
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.pageBg)
        .onAppear { form = sync.settings }
        .alert("云端没有找到同步文件", isPresented: Binding(
            get: { sync.status == .awaitingConfirmation }, set: { _ in }
        )) {
            Button("先检查地址", role: .cancel) {
                sync.cancelPendingSync()
                form = sync.settings
                message = "同步已关闭，请确认服务器地址与手机一致"
            }
            Button("新建同步文件") { sync.confirmCreatingRemoteFile() }
        } message: {
            Text(verbatim: "在 \(sync.remoteFileURL) 没有找到同步文件。\n\n如果手机已经在使用同步，通常是服务器地址不一致（例如少了一层文件夹）。请对照手机「云与同步 → WebDAV」中的地址。\n\n只有这是第一台开始同步的设备时，才选择「新建同步文件」。")
        }
    }

    // MARK: - Groups

    private var serverGroup: some View {
        MiuixGroup(title: "WebDAV 同步") {
            field("服务器地址", "https://dav.jianguoyun.com/dav/", text: $form.serverURL, icon: "server.rack", tint: t.primary)
            field("用户名", "账号邮箱", text: $form.username, icon: "person", tint: Color(hex: 0x8B5CF6))
            MiuixRow(title: "应用密码", systemImage: "key", tint: Color(hex: 0xF59E0B)) {
                SecureField(sync.hasPassword ? "已保存在钥匙串（留空则不修改）" : "第三方应用密码", text: $password)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 260)
            }
            MiuixRow(title: "启用同步", systemImage: "arrow.triangle.2.circlepath", tint: Color(hex: 0x10B981)) {
                Toggle("", isOn: $form.enabled).labelsHidden().toggleStyle(.miuix)
            }
            Text(verbatim: "坚果云：地址填 https://dav.jianguoyun.com/dav/，密码使用「第三方应用管理」中生成的应用密码。同步文件与手机相同：Deadliner/kmp-changelog-v1.json，首次同步以云端（手机）数据为准合并。")
                .font(.system(size: 11.5))
                .foregroundStyle(t.onSurfaceVariant)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            HStack(spacing: 10) {
                if let message {
                    Text(message).font(.system(size: 12)).foregroundStyle(t.onSurfaceVariant)
                }
                Spacer()
                MiuixButton(title: probing ? "检测中…" : "检测服务器") { probe() }
                    .disabled(probing || form.validationError != nil || (password.isEmpty && !sync.hasPassword))
                MiuixButton(title: "保存", kind: .primary) { save() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var probeGroup: some View {
        MiuixGroup(title: "检测结果") {
            ForEach(checks) { check in
                MiuixRow(title: check.title,
                         systemImage: check.state == .ok ? "checkmark" : check.state == .warning ? "exclamationmark" : "xmark",
                         tint: check.state == .ok ? Color(hex: 0x10B981) : check.state == .warning ? Color(hex: 0xF59E0B) : t.error) {
                    Text(check.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(t.onSurfaceVariant)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 330, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var statusGroup: some View {
        MiuixGroup(title: "同步状态") {
            MiuixRow(title: statusText, systemImage: statusIcon, tint: statusTint) {
                MiuixButton(title: "立即同步", kind: .primary) { sync.syncNow() }
                    .disabled(sync.status == .disabled || sync.status == .syncing || sync.status == .backingUp)
            }
            if let backup = sync.lastBackup {
                Text("启用前已备份云端数据：\(backup.lastPathComponent)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.onSurfaceVariant)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
            ForEach(sync.log.prefix(8)) { entry in
                HStack(spacing: 10) {
                    Circle().fill(entry.succeeded ? Color(hex: 0x10B981) : t.error).frame(width: 7, height: 7)
                    Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(t.onSurfaceVariant)
                    Text(entry.succeeded ? (entry.applied > 0 ? "成功，合并了 \(entry.applied) 项云端修改" : "成功") : (entry.message ?? "失败"))
                        .font(.system(size: 12))
                        .foregroundStyle(entry.succeeded ? t.onSurface : t.error)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
    }

    private var appearanceGroup: some View {
        MiuixGroup(title: "外观") {
            MiuixRow(title: "深浅色", systemImage: "circle.lefthalf.filled", tint: Color(hex: 0x6366F1)) {
                Picker("", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var aboutGroup: some View {
        MiuixGroup(title: "关于") {
            MiuixRow(title: "版本", systemImage: "info", tint: t.secondary) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    .foregroundStyle(t.onSurfaceVariant)
            }
            MiuixRow(title: "Core", systemImage: "cpu", tint: t.secondary) {
                Text(MacCoreContainer.coreVersion)
                    .font(.system(size: 11.5).monospaced())
                    .foregroundStyle(t.onSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private func field(_ title: String, _ placeholder: String, text: Binding<String>, icon: String, tint: Color) -> some View {
        MiuixRow(title: title, systemImage: icon, tint: tint) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 260)
        }
    }

    // MARK: - Status

    private var statusText: String {
        switch sync.status {
        case .disabled: "同步未启用"
        case .backingUp: "正在备份云端数据…"
        case .awaitingConfirmation: "等待确认：云端没有找到同步文件"
        case .idle: "等待同步"
        case .syncing: "正在同步…"
        case .succeeded(let date): "上次同步：\(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let reason): "同步失败：\(reason)"
        }
    }

    private var statusIcon: String {
        switch sync.status {
        case .disabled: "icloud.slash"
        case .idle, .syncing, .backingUp: "arrow.triangle.2.circlepath"
        case .awaitingConfirmation: "questionmark.circle"
        case .succeeded: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        }
    }

    private var statusTint: Color {
        switch sync.status {
        case .disabled, .idle, .syncing, .backingUp: t.secondary
        case .awaitingConfirmation: Color(hex: 0xF59E0B)
        case .succeeded: Color(hex: 0x10B981)
        case .failed: t.error
        }
    }

    // MARK: - Actions

    private func save() {
        do {
            try sync.save(form, password: password.isEmpty ? nil : password)
            password = ""
            message = form.enabled ? "已保存，开始同步" : "已保存，同步已关闭"
        } catch {
            message = error.localizedDescription
        }
    }

    private func probe() {
        let probePassword = password.isEmpty
            ? KeychainPasswordStore().password(url: form.normalizedURL, username: form.username) ?? ""
            : password
        probing = true
        checks = []
        let settings = form
        Task {
            let result = await WebDavProbe(settings: settings, password: probePassword).run()
            checks = result
            probing = false
        }
    }
}
