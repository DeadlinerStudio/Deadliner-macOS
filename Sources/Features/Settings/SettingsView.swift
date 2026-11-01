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

/// 衬线字体开关（系统的 serif 设计：拉丁文为 New York，中文由系统选择对应的衬线字形）。
enum FontPreference {
    static let serifKey = "font.serif"
}

/// 设置（系统分组表单）：WebDAV 同步、同步状态、外观、关于。
/// 同时用于侧栏中的「设置」页与 ⌘, 打开的设置窗口。
struct SettingsView: View {
    let sync: SyncController
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage(ThemeAccent.storageKey) private var accentRaw = ThemeAccent.classic.rawValue
    @AppStorage(GlowStyle.storageKey) private var glowRaw = GlowStyle.immersive.rawValue
    @AppStorage(FontPreference.serifKey) private var serif = false
    @AppStorage(MenuBarSettings.enabledKey) private var menuBarEnabled = true
    @AppStorage(MenuBarSettings.styleKey) private var statusStyleRaw = StatusItemStyle.iconCount.rawValue
    @AppStorage(MenuBarSettings.fieldsKey) private var fieldsRaw = StatusField.encode(StatusField.defaults)
    @AppStorage(MenuBarSettings.panelStyleKey) private var panelStyleRaw = PanelStyle.list.rawValue
    @AppStorage(MenuBarSettings.sectionsKey) private var sectionsRaw = PanelSection.encode(PanelSection.defaults)
    @Environment(\.palette) private var t

    @State private var form = SyncSettings(serverURL: "", username: "", enabled: false)
    @State private var password = ""
    @State private var message: String?
    @State private var checks: [WebDavProbe.Check] = []
    @State private var probing = false

    var body: some View {
        Form {
            syncSection
            if !checks.isEmpty { probeSection }
            statusSection
            menuBarSection
            appearanceSection
            aboutSection
        }
        .formStyle(.grouped)
        .readableWidth(760)
        .navigationTitle("设置")
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

    // MARK: - Sections

    private var syncSection: some View {
        Section {
            TextField("服务器地址", text: $form.serverURL, prompt: Text("https://dav.jianguoyun.com/dav/"))
            TextField("用户名", text: $form.username, prompt: Text("账号邮箱"))
            SecureField("应用密码", text: $password, prompt: Text(sync.hasPassword ? "已保存在钥匙串（留空则不修改）" : "第三方应用密码"))
            Toggle("启用同步", isOn: $form.enabled)
            HStack {
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(probing ? "检测中…" : "检测服务器") { probe() }
                    .disabled(probing || form.validationError != nil || (password.isEmpty && !sync.hasPassword))
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("WebDAV 同步")
        } footer: {
            Text(verbatim: "坚果云：地址填 https://dav.jianguoyun.com/dav/ 加上与手机相同的文件夹，密码使用「第三方应用管理」中生成的应用密码。同步文件与手机相同：<地址>/Deadliner/kmp-changelog-v1.json。")
        }
    }

    private var probeSection: some View {
        Section("检测结果") {
            ForEach(checks) { check in
                LabeledContent {
                    Text(check.detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label(check.title, systemImage: check.state == .ok ? "checkmark.circle.fill" : check.state == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(check.state == .ok ? Color.green : check.state == .warning ? Color.orange : Color.red)
                }
            }
        }
    }

    private var statusSection: some View {
        Section("同步状态") {
            HStack {
                Label(statusText, systemImage: statusIcon)
                    .foregroundStyle(statusTint)
                Spacer()
                Button("立即同步") { sync.syncNow() }
                    .disabled(sync.status == .disabled || sync.status == .syncing || sync.status == .backingUp)
            }
            ForEach(sync.log.prefix(8)) { entry in
                LabeledContent(entry.date.formatted(date: .abbreviated, time: .standard)) {
                    Text(entry.succeeded ? (entry.applied > 0 ? "成功，合并了 \(entry.applied) 项云端修改" : "成功") : (entry.message ?? "失败"))
                        .foregroundStyle(entry.succeeded ? Color.secondary : Color.red)
                        .lineLimit(2)
                }
                .font(.callout)
            }
            if let backup = sync.lastBackup {
                LabeledContent("启用前的云端备份") {
                    Text(backup.lastPathComponent).textSelection(.enabled).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private var menuBarSection: some View {
        Section {
            Toggle("在菜单栏显示 Deadliner", isOn: $menuBarEnabled)
            if menuBarEnabled {
                Picker("菜单栏显示", selection: $statusStyleRaw) {
                    ForEach(StatusItemStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if statusStyleRaw == StatusItemStyle.stats.rawValue {
                    ForEach(StatusField.allCases) { field in
                        Toggle(field.title, isOn: Binding(
                            get: { StatusField.decode(fieldsRaw).contains(field) },
                            set: { on in
                                var fields = StatusField.decode(fieldsRaw).filter { $0 != field }
                                if on { fields.append(field) }
                                fields.sort { StatusField.allCases.firstIndex(of: $0)! < StatusField.allCases.firstIndex(of: $1)! }
                                fieldsRaw = StatusField.encode(fields.isEmpty ? [field] : fields)
                            }
                        ))
                        .padding(.leading, 16)
                    }
                }
                Picker("面板风格", selection: $panelStyleRaw) {
                    ForEach(PanelStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                ForEach(PanelSection.allCases) { section in
                    Toggle(section.title, isOn: Binding(
                        get: { PanelSection.decode(sectionsRaw).contains(section) },
                        set: { on in
                            var sections = PanelSection.decode(sectionsRaw).filter { $0 != section }
                            if on { sections.append(section) }
                            sections.sort { PanelSection.allCases.firstIndex(of: $0)! < PanelSection.allCases.firstIndex(of: $1)! }
                            sectionsRaw = PanelSection.encode(sections)
                        }
                    ))
                    .padding(.leading, 16)
                }
            }
        } header: {
            Text("菜单栏")
        } footer: {
            Text("面板使用 Liquid Glass（macOS 26 及以上）；更早的系统使用毛玻璃。")
        }
    }

    private var appearanceSection: some View {
        Section("外观") {
            Picker("深浅色", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("顶部浮光", selection: $glowRaw) {
                ForEach(GlowStyle.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Toggle("衬线字体", isOn: $serif)
            VStack(alignment: .leading, spacing: 8) {
                Text("主题色")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 10) {
                    ForEach(ThemeAccent.allCases) { accentSwatch($0) }
                }
                Text("「经典」与手机配色一致；其他主题会改变主色、「+」按钮与系统控件的颜色，状态色不变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            LabeledContent("Core") {
                Text(MacCoreContainer.coreVersion)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private func accentSwatch(_ accent: ThemeAccent) -> some View {
        let selected = accentRaw == accent.rawValue
        let color = accent.color ?? DeadlinerPalette.of(t.isDark ? .dark : .light).primary
        return Button { accentRaw = accent.rawValue } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(t.onSurface, lineWidth: selected ? 2.5 : 0).padding(-4))
                Text(accent.displayName)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("主题色 \(accent.displayName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        case .disabled, .idle, .syncing, .backingUp: .secondary
        case .awaitingConfirmation: .orange
        case .succeeded: .green
        case .failed: .red
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
        _Concurrency.Task {
            let result = await WebDavProbe(settings: settings, password: probePassword).run()
            checks = result
            probing = false
        }
    }
}
