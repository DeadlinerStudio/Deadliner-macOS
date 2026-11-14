import SwiftUI

/// 从系统日历导入任务（与安卓相同）：列出接下来一段时间的事件，勾选后建成任务。
/// 可以在「日历」菜单中排除不重要的日历（例如节假日、生日），只保存在这台 Mac 上。
struct CalendarImportSheet: View {
    let commands: TaskCommands
    var onClose: () -> Void
    var onImported: (Int) -> Void

    @State private var days = 30
    @State private var calendars: [CalendarBridge.Calendar_] = []
    @State private var excluded = CalendarBridge.excluded()
    @State private var events: [CalendarBridge.Event] = []
    @State private var selected: Set<String> = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("正在读取日历…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("无法读取日历", systemImage: "calendar.badge.exclamationmark", description: Text(errorMessage))
                } else if events.isEmpty {
                    ContentUnavailableView("没有可导入的日历事件", systemImage: "calendar",
                                           description: Text("接下来 \(days) 天内没有事件，或相关日历已被排除。"))
                } else {
                    list
                }
            }
            .navigationTitle("从日历导入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                ToolbarItem(placement: .primaryAction) {
                    Picker("范围", selection: $days) {
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                        Text("90 天").tag(90)
                    }
                    .pickerStyle(.menu)
                    .help("导入接下来多少天内的事件")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(calendars) { calendar in
                            Toggle("\(calendar.title)（\(calendar.source)）", isOn: Binding(
                                get: { !excluded.contains(calendar.id) },
                                set: { include in
                                    if include { excluded.remove(calendar.id) } else { excluded.insert(calendar.id) }
                                    CalendarBridge.setExcluded(excluded)
                                    reload()
                                }
                            ))
                        }
                    } label: {
                        Label("日历", systemImage: "calendar")
                    }
                    .help("选择从哪些日历导入（取消勾选的日历以后也不再显示）")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "导入" : "导入 \(selected.count) 个") { importSelected() }
                        .disabled(selected.isEmpty)
                }
            }
        }
        .frame(width: 520, height: 600)
        .task { await load() }
        .onChange(of: days) { reload() }
    }

    private var list: some View {
        Form {
            Section {
                ForEach(events) { event in
                    Toggle(isOn: Binding(
                        get: { selected.contains(event.id) },
                        set: { if $0 { selected.insert(event.id) } else { selected.remove(event.id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title.isEmpty ? "（无标题）" : event.title)
                            Text("\(Self.time(event)) · \(event.calendarTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            } footer: {
                Text("导入后成为新的任务：截止时间是事件的结束时间（全天事件为当天 23:59）。日历中的事件不会改动。")
            }
        }
        .formStyle(.grouped)
    }

    static func time(_ event: CalendarBridge.Event) -> String {
        if event.isAllDay { return event.start.formatted(.dateTime.month().day().weekday(.abbreviated)) + " 全天" }
        return event.start.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute())
            + " – " + event.end.formatted(.dateTime.hour().minute())
    }

    private func load() async {
        do {
            try await CalendarBridge.shared.requestAccess()
            calendars = CalendarBridge.shared.calendars()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func reload() {
        events = CalendarBridge.shared.upcomingEvents(days: days, excluding: excluded)
        selected = selected.intersection(events.map(\.id))
    }

    private func importSelected() {
        var count = 0
        do {
            for event in events where selected.contains(event.id) {
                try commands.save(CalendarBridge.draft(from: event))
                count += 1
            }
            onImported(count)
        } catch {
            errorMessage = "已导入 \(count) 个，之后出错：\(error.localizedDescription)"
        }
    }
}
