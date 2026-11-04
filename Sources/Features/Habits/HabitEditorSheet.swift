import SwiftUI

/// 习惯编辑器：系统弹窗 + 分组表单（基本信息、颜色与分类、打卡周期、目标与记录方式、提醒）。
struct HabitEditorSheet: View {
    let commands: HabitCommands
    let categories: [CategoryItem]
    var onClose: () -> Void
    /// 保存成功后调用（例如把灵感标记为已整理）。
    var onSaved: (() -> Void)?

    @State private var draft: HabitDraft
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @Environment(\.palette) private var t

    init(commands: HabitCommands, categories: [CategoryItem], draft: HabitDraft, onSaved: (() -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self.onSaved = onSaved
        self.commands = commands
        self.categories = categories
        self.onClose = onClose
        _draft = State(initialValue: draft)
    }

    private var isEditing: Bool { draft.id != nil }
    private static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $draft.name, prompt: Text("习惯名称"))
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .font(.title3.weight(.semibold))
                    TextField("描述", text: $draft.note, prompt: Text("描述"), axis: .vertical)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .lineLimit(2...5)
                }

                Section("颜色与分类") {
                    FlowLayout(spacing: 10) {
                        ForEach(CategoryCommands.colors, id: \.self) { hex in
                            ColorSwatch(hex: hex, selected: draft.colorHex?.uppercased() == hex) { draft.colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                    FlowLayout(spacing: 8) {
                        CategoryChoiceChip(title: "无分类", selected: draft.categoryId == nil) { draft.categoryId = nil }
                        ForEach(categories) { category in
                            CategoryChoiceChip(title: category.name, icon: CategoryIcons.symbol(for: category.iconKey),
                                               color: Color(hexString: category.colorHex), selected: draft.categoryId == category.id) {
                                draft.categoryId = category.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("打卡周期") {
                    Picker("周期", selection: $draft.scheduleKind) {
                        Text("按星期").tag(HabitDraft.ScheduleKind.weeklyDays)
                        Text("一次").tag(HabitDraft.ScheduleKind.once)
                        Text("复习计划").tag(HabitDraft.ScheduleKind.algorithm)
                    }
                    .pickerStyle(.segmented)
                    if draft.scheduleKind == .weeklyDays {
                        HStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { day in
                                WeekdayToggle(title: Self.weekdayNames[day], isOn: draft.weekdaysMask & (1 << day) != 0) {
                                    draft.weekdaysMask ^= (1 << day)
                                }
                            }
                        }
                    } else if draft.scheduleKind == .algorithm {
                        Text("按艾宾浩斯遗忘曲线安排复习日期（与手机相同的算法）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(draft.scheduleKind == .once ? "日期" : "开始日期") {
                        DeadlinerDatePicker(selection: $draft.startOn, components: .date)
                    }
                    if draft.scheduleKind != .once {
                        OptionalDateRow(title: "结束日期", date: $draft.endOn, components: .date) {
                            Calendar.current.date(byAdding: .month, value: 1, to: draft.startOn) ?? draft.startOn
                        }
                    }
                }

                Section("目标与记录方式") {
                    Picker("记录方式", selection: $draft.trackingMode) {
                        Text("打卡").tag(HabitDraft.TrackingMode.checkOff)
                        Text("计量").tag(HabitDraft.TrackingMode.quantity)
                    }
                    .pickerStyle(.segmented)
                    Picker("统计范围", selection: $draft.goalWindow) {
                        Text("每个打卡日").tag(HabitDraft.GoalWindow.scheduledDay)
                        Text("每周").tag(HabitDraft.GoalWindow.week)
                        Text("每月").tag(HabitDraft.GoalWindow.month)
                        Text("累计").tag(HabitDraft.GoalWindow.lifetime)
                    }
                    Stepper(value: $draft.targetCount, in: 1...100_000) {
                        LabeledContent(draft.trackingMode == .quantity ? "目标数量" : "目标次数") {
                            TextField("", value: $draft.targetCount, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 80)
                        }
                    }
                    if draft.trackingMode == .quantity {
                        Stepper(value: $draft.defaultIncrement, in: 1...100_000) {
                            LabeledContent("每次记录") {
                                TextField("", value: $draft.defaultIncrement, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 80)
                            }
                        }
                        TextField("单位", text: $draft.unit, prompt: Text("例如 ml、页、分钟"))
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                    }
                }

                Section {
                    Toggle("每天提醒", isOn: $draft.reminderEnabled)
                    if draft.reminderEnabled {
                        LabeledContent("提醒时间") {
                            DeadlinerDatePicker(selection: $draft.reminderTime, components: .time)
                        }
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("提醒会随同步保存到手机；Mac 端的系统通知会在后续版本支持。")
                }

                if let id = draft.id {
                    FocusStartSection(targetId: id, isHabit: true)
                }

                if isEditing {
                    Section {
                        Button("归档习惯") { perform { try commands.archive(draft.id!) } }
                        Button("删除习惯", role: .destructive) { confirmDelete = true }
                    }
                }

                if let message = errorMessage ?? (draft.name.isEmpty ? nil : draft.validationError) {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "编辑习惯" : "新建习惯")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { perform { try commands.save(draft); onSaved?() } }
                        .disabled(draft.validationError != nil)
                }
            }
        }
        .frame(width: 540, height: 700)
        .confirmationDialog("确定要删除这个习惯吗？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { perform { commands.delete(draft.id!) } }
        } message: {
            Text("打卡记录会一并删除。启用同步后，删除也会同步到手机。")
        }
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

/// 星期选择的圆形按钮。
private struct WeekdayToggle: View {
    let title: String
    let isOn: Bool
    var action: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isOn ? Color.white : t.onSurface)
                .frame(width: 32, height: 32)
                .background(isOn ? t.primary : t.fieldBg, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("周\(title)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 颜色色板中的一个圆点。
struct ColorSwatch: View {
    let hex: String
    let selected: Bool
    var action: () -> Void
    @Environment(\.palette) private var t

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hexString: hex) ?? t.primary)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(t.onSurface, lineWidth: selected ? 2.5 : 0).padding(-4))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("颜色 \(hex)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
