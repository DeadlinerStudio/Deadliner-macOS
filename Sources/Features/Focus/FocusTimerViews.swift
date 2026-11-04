import AppKit
import SwiftUI

/// 任务 / 习惯编辑器中的「专注」：选择倒计时或正计时并开始，显示今天与累计的专注。
/// 开始后打开计时窗；同一时间只能有一个专注（与手机相同）。
struct FocusStartSection: View {
    let targetId: String
    let isHabit: Bool
    @Environment(\.focusTimer) private var timer
    @Environment(\.openWindow) private var openWindow
    @AppStorage(FocusTimerWindow.countdownKey) private var countdown = true
    @AppStorage(FocusTimerWindow.minutesKey) private var minutes = 25

    var body: some View {
        if let timer {
            Section {
                if let running = timer.running {
                    if running.targetId == targetId {
                        HStack {
                            Label(running.isRunning ? "专注中" : "已暂停", systemImage: running.isRunning ? "timer" : "pause.circle")
                            Spacer()
                            Text(FocusTimerStore.clock(running.displaySeconds)).monospacedDigit()
                            Button("打开计时窗") { openWindow(id: FocusTimerWindow.id) }
                        }
                    } else {
                        HStack {
                            Text("正在专注「\(running.title)」，结束后才能开始新的专注")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("查看") { openWindow(id: FocusTimerWindow.id) }
                        }
                    }
                } else {
                    Picker("计时方式", selection: $countdown) {
                        Text("倒计时").tag(true)
                        Text("正计时").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if countdown {
                        FocusDurationChooser(minutes: $minutes)
                    }
                    Button("开始专注") {
                        if isHabit { timer.startHabit(targetId, minutes: countdown ? minutes : nil) }
                        else { timer.startTask(targetId, minutes: countdown ? minutes : nil) }
                        openWindow(id: FocusTimerWindow.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(timer.isBusy)
                }
                if !isHabit {
                    LabeledContent("今天专注", value: FocusTexts.duration(timer.selectedTaskTodaySeconds))
                    LabeledContent("累计专注", value: FocusTexts.duration(timer.selectedTaskTotalSeconds))
                }
                if let message = timer.errorMessage, timer.running == nil {
                    Text(message).foregroundStyle(.red)
                }
            } header: {
                Text("专注")
            } footer: {
                Text("专注记录会同步到手机；正在进行的计时只在这台 Mac 上。")
            }
            .onAppear { if !isHabit { timer.selectTask(targetId) } }
        }
    }
}

/// 倒计时时长：常用时长 + 自定义分钟数。
struct FocusDurationChooser: View {
    @Binding var minutes: Int
    @Environment(\.palette) private var t

    var body: some View {
        HStack(spacing: 6) {
            ForEach([15, 25, 45, 60], id: \.self) { value in
                Button("\(value) 分钟") { minutes = value }
                    .buttonStyle(.plain)
                    .font(.callout.weight(minutes == value ? .semibold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(minutes == value ? t.primary.opacity(0.18) : t.fieldBg, in: Capsule())
                    .foregroundStyle(minutes == value ? t.primary : t.onSurface)
            }
            Spacer()
            Stepper("\(minutes) 分钟", value: $minutes, in: 1...180)  // Core 允许 1～180 分钟
                .monospacedDigit()
        }
    }
}

/// 计时窗：可以置顶的小窗口，切到其他应用也看得到。关闭窗口不会结束计时。
enum FocusTimerWindow {
    static let id = "focus-timer"
    static let countdownKey = "focus.countdown"
    static let minutesKey = "focus.minutes"
    static let pinnedKey = "focus.pinned"
}

struct FocusTimerWindowView: View {
    let timer: FocusTimerStore
    @AppStorage(FocusTimerWindow.pinnedKey) private var pinned = true
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.palette) private var t

    var body: some View {
        VStack(spacing: 0) {
            if let running = timer.running {
                FocusRunningView(timer: timer, running: running)
            } else if let result = timer.result {
                FocusResultView(timer: timer, result: result) {
                    timer.dismissResult()
                    dismissWindow(id: FocusTimerWindow.id)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "timer").font(.system(size: 34)).foregroundStyle(t.primary)
                    Text("没有进行中的专注").font(.headline)
                    Text("打开任务或习惯，在「专注」中开始。").font(.callout).foregroundStyle(.secondary)
                    Text("今天已专注 \(FocusTexts.duration(timer.todaySeconds))").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(width: 320, height: 380)
        .background(WindowLevelSetter(floating: pinned))
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $pinned) { Label("置顶", systemImage: pinned ? "pin.fill" : "pin") }
                    .help(pinned ? "取消置顶" : "置顶计时窗")
            }
        }
        .navigationTitle("专注")
    }
}

/// 计时中：时间、进度环与操作。
struct FocusRunningView: View {
    let timer: FocusTimerStore
    let running: FocusTimerStore.Running
    @State private var amount = 1
    @State private var confirmDiscard = false
    @Environment(\.palette) private var t

    var body: some View {
        VStack(spacing: 14) {
            Label(running.title, systemImage: running.isHabit ? "leaf" : "checklist")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            ZStack {
                Circle().stroke(t.primary.opacity(0.12), lineWidth: 10)
                if let progress = running.progress {
                    Circle()
                        .trim(from: 0, to: 1 - progress)
                        .stroke(t.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                }
                VStack(spacing: 2) {
                    Text(FocusTimerStore.clock(running.displaySeconds))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(running.isRunning ? (running.isCountdown ? "剩余" : "已专注") : "已暂停")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, height: 170)

            if let warning = timer.warning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if let message = timer.errorMessage {
                Text(message).font(.caption).foregroundStyle(t.error)
            }

            HStack(spacing: 10) {
                if running.canResume {
                    Button("继续") { timer.resume() }.keyboardShortcut(.space, modifiers: [])
                } else {
                    Button("暂停") { timer.pause() }.disabled(!running.canPause).keyboardShortcut(.space, modifiers: [])
                }
                Button("结束") { timer.finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!running.canFinish)
                Menu {
                    if !running.isHabit {
                        Button("结束并完成任务") { timer.finishAndCompleteTask() }.disabled(!running.canFinishAndComplete)
                    }
                    Button("放弃这次专注", role: .destructive) { confirmDiscard = true }
                } label: { Image(systemName: "ellipsis") }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .controlSize(.large)
            .disabled(timer.isBusy)

            if let habit = running.habit, running.isHabit {
                HStack {
                    if habit.isQuantity {
                        Stepper("\(amount)\(habit.unit ?? "")", value: $amount, in: 1...9999).monospacedDigit()
                    }
                    Button("结束并打卡") { timer.finishAndRecordHabit(amount: habit.isQuantity ? amount : nil) }
                        .disabled(!running.canFinishAndRecord || timer.isBusy)
                }
                .font(.callout)
                Text("今日 \(habit.completed)/\(habit.target)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("放弃这次专注？", isPresented: $confirmDiscard) {
            Button("放弃", role: .destructive) { timer.discard() }
        } message: {
            Text("这次计时不会保存为专注记录。")
        }
    }
}

/// 结束后：专注了多久，任务可以直接完成。
struct FocusResultView: View {
    let timer: FocusTimerStore
    let result: FocusTimerStore.Result
    var close: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(t.completedCheck)
            Text("专注完成").font(.title3.weight(.semibold))
            Text(result.title).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            Text("本次专注 \(FocusTexts.duration(result.seconds))").foregroundStyle(.secondary)
            if result.isHabit {
                if result.recordedHabit { Label("已打卡", systemImage: "checkmark").foregroundStyle(t.completedCheck) }
            } else if result.taskCompleted {
                Label("任务已完成", systemImage: "checkmark").foregroundStyle(t.completedCheck)
            } else if result.canCompleteTask {
                Button("完成任务") { timer.completeSavedTask() }.buttonStyle(.borderedProminent).disabled(timer.isBusy)
            }
            if let message = timer.errorMessage {
                Text(message).font(.caption).foregroundStyle(t.error)
            }
            Button("关闭", action: close).keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 菜单栏：计时进行中时显示计时（替代平时的图标与数量）。
struct FocusStatusLabel: View {
    let running: FocusTimerStore.Running

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: running.isRunning ? "timer" : "pause.circle")
                .font(.system(size: 13, weight: .medium))
            Text(FocusTimerStore.clock(running.displaySeconds))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 5)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在专注 \(running.title)，\(FocusTimerStore.clock(running.displaySeconds))")
    }
}

/// 菜单栏面板顶部：正在进行的专注，可以暂停 / 继续 / 结束，点击打开计时窗。
struct FocusPanelTimerRow: View {
    let timer: FocusTimerStore
    let running: FocusTimerStore.Running
    var open: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: running.isRunning ? "timer" : "pause.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(t.primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(running.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(running.isRunning ? (running.isCountdown ? "剩余" : "已专注") : "已暂停")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(FocusTimerStore.clock(running.displaySeconds))
                        .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开计时窗")
            Button { running.canResume ? timer.resume() : timer.pause() } label: {
                Image(systemName: running.canResume ? "play.fill" : "pause.fill")
            }
            .help(running.canResume ? "继续" : "暂停")
            .disabled(timer.isBusy || !(running.canResume || running.canPause))
            Button { timer.finish() } label: { Image(systemName: "stop.fill") }
                .help("结束")
                .disabled(timer.isBusy || !running.canFinish)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(t.primary.opacity(0.10))
    }
}

/// 把所在窗口设为浮动（置顶）或普通层级。
private struct WindowLevelSetter: NSViewRepresentable {
    let floating: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.level = floating ? .floating : .normal
            view.window?.collectionBehavior.insert(.fullScreenAuxiliary)
        }
    }
}
