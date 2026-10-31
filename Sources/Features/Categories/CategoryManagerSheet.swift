import SwiftUI

/// 分类管理：新建、编辑、删除，以及恢复预设分类。
struct CategoryManagerSheet: View {
    let commands: CategoryCommands
    var onClose: () -> Void

    @State private var categories: [CategoryItem] = []
    @State private var editing: CategoryForm?
    @State private var pendingDelete: CategoryItem?
    @State private var errorMessage: String?
    @Environment(\.palette) private var t

    struct CategoryForm: Identifiable {
        var id: String?
        var name = ""
        var iconKey = "folder"
        var colorHex = CategoryCommands.colors[0]
        var formId: String { id ?? "new" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("管理分类")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(t.onSurface)
                .padding(.vertical, 16)

            if let form = Binding($editing) {
                CategoryFormView(form: form)
                    .padding(.horizontal, 22)
            } else {
                ScrollView {
                    MiuixGroup {
                        ForEach(categories) { category in
                            MiuixRow(title: category.name, systemImage: CategoryIcons.symbol(for: category.iconKey),
                                     tint: Color(hexString: category.colorHex)) {
                                Button("编辑") { editing = CategoryForm(id: category.id, name: category.name,
                                                                       iconKey: category.iconKey, colorHex: category.colorHex) }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(t.primary)
                                Button("删除") { pendingDelete = category }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(t.error)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(t.error).padding(.top, 6)
            }

            HStack(spacing: 10) {
                if editing != nil {
                    Spacer()
                    MiuixButton(title: "取消") { editing = nil }
                        .keyboardShortcut(.cancelAction)
                    MiuixButton(title: "保存", kind: .primary) { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(editing?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                } else {
                    MiuixButton(title: "恢复预设") { commands.restorePresets(); reload() }
                    Spacer()
                    MiuixButton(title: "新建分类") { editing = CategoryForm() }
                    MiuixButton(title: "完成", kind: .primary) { onClose() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(t.groupBg)
        }
        .frame(width: 480, height: 560)
        .background(t.pageBg)
        .onAppear(perform: reload)
        .confirmationDialog("删除分类「\(pendingDelete?.name ?? "")」？", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let category = pendingDelete { run { try commands.delete(id: category.id) } }
                pendingDelete = nil
            }
        } message: {
            Text("使用这个分类的任务会变成无分类。启用同步后，删除也会同步到手机。")
        }
    }

    private func reload() { categories = commands.list() }

    private func save() {
        guard let form = editing else { return }
        run {
            if let id = form.id {
                try commands.update(id: id, name: form.name, iconKey: form.iconKey, colorHex: form.colorHex)
            } else {
                try commands.create(name: form.name, iconKey: form.iconKey, colorHex: form.colorHex)
            }
            editing = nil
        }
    }

    private func run(_ body: () throws -> Void) {
        do {
            try body()
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 新建 / 编辑分类的表单：名称、图标、颜色。
private struct CategoryFormView: View {
    @Binding var form: CategoryManagerSheet.CategoryForm
    @Environment(\.palette) private var t

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MiuixTextField(placeholder: "分类名称", text: $form.name, font: .system(size: 15, weight: .semibold))
                MiuixGroup(title: "颜色") {
                    FlowLayout(spacing: 10) {
                        ForEach(CategoryCommands.colors, id: \.self) { hex in
                            let color = Color(hexString: hex) ?? t.primary
                            Button { form.colorHex = hex } label: {
                                Circle().fill(color).frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(t.onSurface, lineWidth: form.colorHex.uppercased() == hex ? 2.5 : 0).padding(-4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                }
                MiuixGroup(title: "图标") {
                    FlowLayout(spacing: 8) {
                        ForEach(CategoryCommands.iconKeys, id: \.self) { key in
                            let selected = form.iconKey == key
                            let color = Color(hexString: form.colorHex) ?? t.primary
                            Button { form.iconKey = key } label: {
                                Image(systemName: CategoryIcons.symbol(for: key))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(selected ? .white : t.onSurface)
                                    .frame(width: 34, height: 34)
                                    .background(selected ? color : t.fieldBg, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}
