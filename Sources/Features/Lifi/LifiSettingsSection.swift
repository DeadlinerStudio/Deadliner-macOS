import SwiftUI
import Shared

/// 设置中的「Lifi AI」：与安卓相同的 BYOK（自带服务地址、模型和 API Key）与交互偏好，以及记忆管理。
/// 服务配置与月度洞察共用（钥匙串中的同一条密钥）。
struct LifiSettingsSection: View {
    var database: DeadlinerDatabase?
    var onChange: () -> Void = {}

    @AppStorage(LifiSettings.enabledKey) private var enabled = false
    @AppStorage(LifiSettings.autoApproveReadKey) private var autoApproveRead = false
    @AppStorage(LifiSettings.silentAddKey) private var silentAdd = false
    @AppStorage(LifiSettings.hideThinkingKey) private var hideThinking = false
    @State private var url = UserDefaults.standard.string(forKey: LifiSettings.urlKey) ?? ""
    @State private var model = UserDefaults.standard.string(forKey: LifiSettings.modelKey) ?? ""
    @State private var key = ""
    @State private var message: String?
    @State private var probing = false
    @State private var managingMemory = false
    @State private var customPrompt = UserDefaults.standard.string(forKey: LifiSettings.customPromptKey) ?? ""
    @State private var promptSaved = false

    var body: some View {
        Group { content }
            .onAppear { key = LifiSettings.apiKey(url: url) ?? "" }
            .sheet(isPresented: $managingMemory) {
                if let database { LifiMemorySheet(database: database) { managingMemory = false }.deadlinerTheme() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !LifiSettings.isAvailable {
            Section {
                Text("当前构建未包含 Lifi AI（公开构建）。").foregroundStyle(.secondary)
            }
        } else {
            Section {
                Toggle("启用 Lifi AI", isOn: $enabled)
            } footer: {
                Text("启用后可以在 Lifi 对话窗口（⌘L）中让 AI 安排任务、建立习惯、回答关于任务的问题，并在快速添加中使用 AI 识别。只会连接下面填写的服务。")
            }
            Section {
                TextField("服务地址（含 /v1）", text: $url, prompt: Text("https://api.deepseek.com/v1"))
                TextField("模型 ID", text: $model, prompt: Text("deepseek-chat"))
                SecureField("API Key", text: $key)
                HStack {
                    if let message {
                        Text(message).font(.caption).textSelection(.enabled)
                            .foregroundStyle(message.hasPrefix("连接正常") || message.hasPrefix("已保存") ? Color.green : Color.red)
                    }
                    Spacer()
                    Button(probing ? "测试中…" : "测试连接") { probe() }
                        .disabled(probing || url.isEmpty || model.isEmpty || key.isEmpty)
                    Button("保存", action: save)
                }
            } header: {
                Text("API 配置（BYOK）")
            } footer: {
                Text("使用兼容 Chat Completions 的服务；与「概览 → 月度洞察」共用这份配置。密钥保存在钥匙串。")
            }
            Section("交互偏好") {
                Toggle("自动确认读取任务列表", isOn: $autoApproveRead)
                Text("Lifi 需要读取任务或习惯时不再询问。").font(.caption).foregroundStyle(.secondary)
                Toggle("静默添加任务", isOn: $silentAdd)
                Text("AI 提出的任务和习惯直接添加（可以在对话中撤回），不再逐条确认。").font(.caption).foregroundStyle(.secondary)
                Toggle("隐藏思考过程", isOn: $hideThinking)
                Text("不显示「正在思考」「等待工具结果」等过程信息。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextEditor(text: $customPrompt)
                    .font(.body)
                    .frame(minHeight: 80)
                    .onChange(of: customPrompt) {
                        promptSaved = false
                        if customPrompt.count > LifiSettings.customPromptLimit {
                            customPrompt = String(customPrompt.prefix(LifiSettings.customPromptLimit))
                        }
                    }
                HStack {
                    if promptSaved { Text("提示词已保存").font(.caption).foregroundStyle(.green) }
                    Spacer()
                    Button("保存提示词") {
                        UserDefaults.standard.set(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines), forKey: LifiSettings.customPromptKey)
                        promptSaved = true
                    }
                    .disabled(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == LifiSettings.customPrompt)
                }
            } header: {
                Text("自定义提示词")
            } footer: {
                Text("与安卓相同：从一段文字中识别任务（快速添加的「AI 识别」）时，这段话会附在原文之前，例如「默认截止时间为当天 23:59」「课程名放在标题开头」。留空则不附加。")
            }
            if database != nil {
                Section {
                    Button("记忆管理…") { managingMemory = true }
                } footer: {
                    Text("用户画像与碎片记忆，供 Lifi 了解你的偏好；随同步在设备之间保持一致。")
                }
            }
        }
    }

    private func probe() {
        probing = true
        message = nil
        let (url, model, key) = (url, model, key)
        _Concurrency.Task {
            message = await MonthlyInsightSettings.probe(url: url, model: model, key: key)
            probing = false
        }
    }

    private func save() {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let parsed = URL(string: address), parsed.scheme == "https", parsed.host != nil, parsed.user == nil, parsed.password == nil,
              !model.trimmingCharacters(in: .whitespaces).isEmpty, !key.isEmpty else {
            message = "请填写 HTTPS 服务地址、模型和 API Key"
            return
        }
        guard MonthlyInsightSettings.keychain.setPassword(key, url: address, username: "api") else {
            message = "钥匙串保存失败"
            return
        }
        UserDefaults.standard.set(address, forKey: LifiSettings.urlKey)
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespaces), forKey: LifiSettings.modelKey)
        url = address
        message = "已保存"
        onChange()
    }
}
