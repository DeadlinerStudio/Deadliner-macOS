import SwiftUI

/// 习惯编辑器（与任务编辑器同样的底部弹出面板样式）：
/// 基本信息、打卡周期、目标、记录方式、提醒。
struct HabitEditorSheet: View {
    let commands: HabitCommands
    let categories: [CategoryItem]
    var onClose: () -> Void

    @State private var draft: HabitDraft
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @Environment(\.miuix) private var t

    init(commands: HabitCommands, categories: [CategoryItem], draft: HabitDraft, onClose: @escaping () -> Void) {
        self.commands = commands
        self.categories = categories
        self.onClose = onClose
        _draft = State(initialValue: draft)
    }

    private var isEditing: Bool { draft.id != nil }
    private static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(t.onSurfaceVariant.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
            Text(isEditing ? "编辑习惯" : "新建习惯")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(t.onSurface)
                .padding(.top, 12)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MiuixTextField(placeholder: "习惯名称", text: $draft.name, font: .system(size: 16, weight: .semibold))
                    MiuixTextField(placeholder: "描述", text: $draft.note, axis: .vertical)
                    appearanceGroup
                    scheduleGroup
                    goalGroup
                    reminderGroup
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }

            if let message = errorMessage ?? draft.validationError, !draft.name.isEmpty || errorMessage != nil {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(t.error)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 6)
            }
            bottomBar
        }
        .frame(width: 540, height: 700)
        .background(t.pageBg)
        .confirmationDialog("确定要删除这个习惯吗？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { perform { commands.delete(draft.id!) } }
        } message: {
            Text("打卡记录会一并删除。启用同步后，删除也会同步到手机。")
        }
    }

    // MARK: - Groups

    private var appearanceGroup: some View {
        MiuixGroup(title: "颜色与分类") {
            FlowLayout(spacing: 10) {
                ForEach(CategoryCommands.colors, id: \.self) { hex in
                    let color = Color(hexString: hex) ?? t.primary
                    Button { draft.colorHex = hex } label: {
                        Circle().fill(color).frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(t.onSurface, lineWidth: draft.colorHex?.uppercased() == hex ? 2.5 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            FlowLayout(spacing: 8) {
                chip("无分类", selected: draft.categoryId == nil) { draft.categoryId = nil }
                ForEach(categories) { category in
                    chip(category.name, icon: CategoryIcons.symbol(for: category.iconKey), color: Color(hexString: category.colorHex),
                         selected: draft.categoryId == category.id) { draft.categoryId = category.id }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var scheduleGroup: some View {
        MiuixGroup(title: "打卡周期") {
            MiuixSegmented(selection: $draft.scheduleKind, options: [
                (.weeklyDays, "按星期"), (.once, "一次"), (.algorithm, "复习计划"),
            ])
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if draft.scheduleKind == .weeklyDays {
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { day in
                        let on = draft.weekdaysMask & (1 << day) != 0
                        Button { draft.weekdaysMask ^= (1 << day) } label: {
                            Text(Self.weekdayNames[day])
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(on ? .white : t.onSurface)
                                .frame(width: 34, height: 34)
                                .background(on ? t.primary : t.fieldBg, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            } else if draft.scheduleKind == .algorithm {
                Text("按艾宾浩斯遗忘曲线安排复习日期（与手机相同的算法）。")
                    .font(.system(size: 12))
                    .foregroundStyle(t.onSurfaceVariant)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            MiuixRow(title: draft.scheduleKind == .once ? "日期" : "开始日期", systemImage: "calendar", tint: t.secondary) {
                DatePicker("", selection: $draft.startOn, displayedComponents: .date).labelsHidden()
            }
            if draft.scheduleKind != .once {
                MiuixRow(title: "结束日期", systemImage: "calendar.badge.clock", tint: t.tertiary) {
                    if let end = draft.endOn {
                        DatePicker("", selection: Binding(get: { end }, set: { draft.endOn = $0 }), displayedComponents: .date).labelsHidden()
                    }
                    Toggle("", isOn: Binding(
                        get: { draft.endOn != nil },
                        set: { draft.endOn = $0 ? Calendar.current.date(byAdding: .month, value: 1, to: draft.startOn) : nil }
                    ))
                    .labelsHidden()
                    .toggleStyle(.miuix)
                }
            }
        }
    }

    private var goalGroup: some View {
        MiuixGroup(title: "目标与记录方式") {
            MiuixSegmented(selection: $draft.trackingMode, options: [(.checkOff, "打卡"), (.quantity, "计量")])
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            MiuixRow(title: "统计范围", systemImage: "chart.bar", tint: t.primary) {
                Picker("", selection: $draft.goalWindow) {
                    Text("每个打卡日").tag(HabitDraft.GoalWindow.scheduledDay)
                    Text("每周").tag(HabitDraft.GoalWindow.week)
                    Text("每月").tag(HabitDraft.GoalWindow.month)
                    Text("累计").tag(HabitDraft.GoalWindow.lifetime)
                }
                .labelsHidden()
                .fixedSize()
            }
            MiuixRow(title: draft.trackingMode == .quantity ? "目标数量" : "目标次数", systemImage: "flag.checkered", tint: Color(hex: 0x10B981)) {
                numberField($draft.targetCount)
            }
            if draft.trackingMode == .quantity {
                MiuixRow(title: "每次记录", systemImage: "plus.circle", tint: Color(hex: 0xF59E0B)) {
                    numberField($draft.defaultIncrement)
                }
                MiuixRow(title: "单位", systemImage: "ruler", tint: Color(hex: 0x06B6D4)) {
                    TextField("例如 ml、页、分钟", text: $draft.unit)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                }
            }
        }
    }

    private var reminderGroup: some View {
        MiuixGroup(title: "提醒") {
            MiuixRow(title: "每天提醒", systemImage: "bell", tint: t.error) {
                if draft.reminderEnabled {
                    DatePicker("", selection: $draft.reminderTime, displayedComponents: .hourAndMinute).labelsHidden()
                }
                Toggle("", isOn: $draft.reminderEnabled).labelsHidden().toggleStyle(.miuix)
            }
            Text("提醒会随同步保存到手机；Mac 端的系统通知会在后续版本支持。")
                .font(.system(size: 11.5))
                .foregroundStyle(t.onSurfaceVariant)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }

    private func numberField(_ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Stepper("", value: value, in: 1...100_000).labelsHidden()
        }
    }

    private func chip(_ title: String, icon: String? = nil, color: Color? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        let tint = color ?? t.onSurfaceVariant
        return Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(selected ? Color.white : tint)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(selected ? tint : tint.opacity(t.isDark ? 0.22 : 0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if isEditing {
                MiuixButton(title: "删除", kind: .destructive) { confirmDelete = true }
                MiuixButton(title: "归档") { perform { try commands.archive(draft.id!) } }
            }
            Spacer()
            MiuixButton(title: "取消") { onClose() }
                .keyboardShortcut(.cancelAction)
            MiuixButton(title: "保存", kind: .primary) { perform { try commands.save(draft) } }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationError != nil)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(t.groupBg)
    }

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
