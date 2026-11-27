import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MonthlyInsightContent: View {
    let store: MonthlyInsightStore
    let review: OverviewStore.MonthReview
    @State private var settings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.loading { ProgressView("正在生成月度洞察…") }
            else if let result = store.result, result.month == review.monthStart {
                Text(result.summary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 6) {
                    ForEach(Array(result.keywords.enumerated()), id: \.offset) { _, keyword in
                        Text(keyword).font(.caption).padding(7).background(.purple.opacity(0.1), in: Capsule())
                    }
                }
            } else if store.monthInProgress {
                Text("这个月还没结束，月底之后可以生成洞察").foregroundStyle(.secondary)
            } else if store.awaitingRequest {
                Text("这个月还没有生成洞察").foregroundStyle(.secondary)
                HStack {
                    Button("生成洞察") { store.resolve(review: review, retry: true) }.disabled(review.monthStart == nil)
                    Button("AI 配置") { settings = true }
                }
            } else {
                Text(store.error ?? String(localized: "月度洞察尚未生成")).foregroundStyle(.secondary)
                HStack {
                    Button("AI 配置") { settings = true }
                    Button("重试") { store.resolve(review: review, retry: true) }.disabled(review.monthStart == nil)
                }
            }
        }
        .sheet(isPresented: $settings) {
            MonthlyInsightSettingsView { store.resolve(review: review, retry: true) }
        }
    }
}

struct MonthlyInsightSettingsView: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = UserDefaults.standard.string(forKey: "overview.ai.url") ?? ""
    @State private var model = UserDefaults.standard.string(forKey: "overview.ai.model") ?? ""
    @State private var enabled = UserDefaults.standard.bool(forKey: "overview.ai.enabled")
    @State private var key = ""
    @State private var error: String?
    @State private var probeResult: String?
    @State private var probing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("月度洞察配置").font(.title2.bold())
            Form {
                Toggle("启用月度洞察", isOn: $enabled)
                TextField("服务地址（含 /v1）", text: $url)
                TextField("模型", text: $model)
                SecureField("API Key", text: $key)
            }
            Text("使用兼容 Chat Completions 的服务。启用后会向该服务发送月度指标和最多 50 个已完成任务标题，生成结果按月保存在本机；密钥保存在钥匙串。")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            if let probeResult {
                Text(probeResult).font(.caption).textSelection(.enabled)
                    .foregroundStyle(probeResult.hasPrefix(String(localized: "连接正常")) ? Color.green : Color.red)
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(probing ? "测试中…" : "测试连接") {
                    probing = true
                    probeResult = nil
                    let (url, model, key) = (url, model, key)
                    _Concurrency.Task {
                        let result = await MonthlyInsightSettings.probe(url: url, model: model, key: key)
                        probeResult = result
                        probing = false
                    }
                }
                .disabled(probing || url.isEmpty || model.isEmpty || key.isEmpty)
                Button("保存", action: save).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 480)
            .onAppear { key = MonthlyInsightSettings.keychain.password(url: url, username: "api") ?? "" }
    }
    private func save() {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if enabled {
            guard let parsed = URL(string: address), parsed.scheme == "https", parsed.host != nil,
                  parsed.user == nil, parsed.password == nil,
                  !model.trimmingCharacters(in: .whitespaces).isEmpty, !key.isEmpty else {
                error = String(localized: "请填写 HTTPS 服务地址、模型和 API Key"); return
            }
            guard MonthlyInsightSettings.keychain.setPassword(key, url: address, username: "api") else {
                error = String(localized: "钥匙串保存失败"); return
            }
        }
        UserDefaults.standard.set(address, forKey: "overview.ai.url")
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespaces), forKey: "overview.ai.model")
        UserDefaults.standard.set(enabled, forKey: "overview.ai.enabled")
        onSave(); dismiss()
    }
}

/// 月度复盘：与总览共用月份选择（上方的月份切换），可以查看任意月份。
struct OverviewReviewWorkspace<Controls: View>: View {
    let store: OverviewStore
    let insight: MonthlyInsightStore
    let columns: Int
    /// 所选月份（月初）。
    let month: Date
    @ViewBuilder var controls: Controls
    @State private var export = false
    @State private var settings = false

    private var review: OverviewStore.MonthReview? { store.month?.review }
    private var inProgress: Bool { month >= OverviewPeriod.month() }

    var body: some View {
        HStack {
            Text("月度复盘").font(.title2.bold())
            Spacer()
            Button("AI 配置") { settings = true }
            Button("导出与分享", systemImage: "square.and.arrow.up") { export = true }
                .disabled(review?.monthStart == nil || store.monthLoading)
        }
        controls
        Text(inProgress ? "本月进行中，数据统计到今天 · 指标按截止日期，活动按完成日期；逾期指标含放弃任务。"
                        : "指标按截止日期，活动按完成日期；逾期指标含放弃任务。")
            .font(.caption).foregroundStyle(.secondary)
        if let error = store.monthError { OverviewError(message: error) { store.loadMonth(OverviewPeriod.key(month)) } }
        else if let review, !store.monthLoading {
            OverviewCard(title: String(localized: "AI 月度洞察")) { MonthlyInsightContent(store: insight, review: review) }
            OverviewMetricsCard(review: review)
            OverviewRow(columns: min(columns, 2)) {
                OverviewActivityCalendar(review: review).frame(maxWidth: .infinity)
                OverviewTitlesCard(review: review).frame(maxWidth: .infinity)
            }
        } else { ProgressView("加载复盘…").frame(maxWidth: .infinity, minHeight: 200) }
        Color.clear.frame(height: 0)
            .sheet(isPresented: $export) {
                if let review { OverviewReviewExport(review: review, insight: insight.result?.month == review.monthStart ? insight.result : nil) }
            }
            .sheet(isPresented: $settings) {
                MonthlyInsightSettingsView { if let review { insight.resolve(review: review, retry: true) } }
            }
    }
}

struct OverviewReviewExport: View {
    let review: OverviewStore.MonthReview
    let insight: MonthlyInsight?
    @Environment(\.dismiss) private var dismiss
    @State private var darkText = true
    @State private var background: NSImage?
    @State private var rendered: NSImage?
    @State private var message: String?
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("导出月度复盘").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
            }
            HStack {
                Toggle("深色文字", isOn: $darkText)
                Button("选择背景图", action: chooseBackground)
                if background != nil { Button("移除背景") { background = nil } }
                Spacer()
                Button("保存 PNG", action: save)
                Button("系统分享", action: share)
            }
            ScrollView { poster.frame(width: 620) }.frame(maxWidth: .infinity)
            if let message { Text(message).foregroundStyle(.secondary) }
        }.padding(24).frame(width: 760, height: 720)
    }
    private var poster: some View {
        OverviewReviewPoster(review: review, insight: insight, darkText: darkText, background: background)
    }
    private func render() -> NSImage? {
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 2
        return renderer.nsImage
    }
    private func chooseBackground() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            if response == .OK, let url = panel.url { background = NSImage(contentsOf: url) }
        }
    }
    private func save() {
        guard let image = render(), let data = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else {
            message = String(localized: "无法生成复盘图片"); return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = String(localized: "Deadliner-复盘-\(review.monthStart ?? String(localized: "上月")).png")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try png.write(to: url, options: .atomic); message = String(localized: "已保存复盘图片") }
            catch { message = String(localized: "保存失败：\(error.localizedDescription)") }
        }
    }
    private func share() {
        guard let image = render(), let view = NSApp.keyWindow?.contentView else { message = String(localized: "无法生成分享图片"); return }
        rendered = image
        NSSharingServicePicker(items: [image]).show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 50, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
}

/// 同一份纯展示内容供预览、导出与渲染验证使用。
struct OverviewReviewPoster: View {
    let review: OverviewStore.MonthReview
    let insight: MonthlyInsight?
    var darkText = true
    var background: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Deadliner · 月度复盘").font(.headline)
            Text(review.monthStart.map { OverviewDates.label($0, String(localized: "yyyy 年 M 月")) } ?? String(localized: "上月")).font(.largeTitle.bold())
            if let insight, insight.month == review.monthStart {
                Text(insight.summary).fixedSize(horizontal: false, vertical: true)
                Text(insight.keywords.joined(separator: " · ")).font(.callout)
            }
            Divider()
            HStack {
                metric(String(localized: "任务总数"), "\(review.totalTasks)")
                metric(String(localized: "已完成"), "\(review.completedTasks)")
                metric(String(localized: "完成率"), OverviewMetricsCard.percent(review.completionRate))
            }
            HStack {
                metric(String(localized: "逾期"), "\(review.overdueTasks)")
                metric(String(localized: "活跃时段"), review.mostActivePeriod?.title ?? "—")
                metric(String(localized: "平均完成用时"), review.averageCompletionMinutes.map(OverviewMetricsCard.minutes) ?? "—")
            }
            Text("每日完成活动").font(.headline)
            let weeks = OverviewHeatmapCard.weeks(review.daily)
            HStack { ForEach(Array(AppLanguage.weekdays().enumerated()), id: \.offset) { Text($0.element).frame(maxWidth: .infinity) } }
            ForEach(weeks.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { day in
                        let item = weeks[index][day]
                        Text(item.map { OverviewDates.label($0.date, "d") } ?? " ")
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(Color.green.opacity(item == nil ? 0 : item!.completed == 0 ? 0.08 : min(0.75, 0.2 + Double(item!.completed) * 0.1)), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Text("指标按截止月份统计，活动按完成日期统计；逾期指标含放弃。AI 洞察为该月已保存结果。")
                .font(.caption)
        }
        .padding(32).frame(width: 620)
        .foregroundStyle(darkText ? Color.black : .white)
        .background {
            GeometryReader { proxy in
                if let background { Image(nsImage: background).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped() }
                else { LinearGradient(colors: darkText ? [Color(red: 0.9, green: 0.95, blue: 1), .white] : [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing) }
            }
        }
    }
    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(name).font(.caption); Text(value).font(.title2.bold()) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
