import SwiftUI

/// 分类管理：系统分组表单；列表中新建、编辑、删除，以及恢复预设分类。
struct CategoryManagerSheet: View {
    let commands: CategoryCommands
    var onClose: () -> Void

    @State private var categories: [CategoryItem] = []
    @State private var editing: CategoryForm?
    @State private var pendingDelete: CategoryItem?
    @State private var errorMessage: String?
    @Environment(\.palette) private var t

    struct CategoryForm {
        var id: String?
        var name = ""
        var iconKey = "folder"
        var colorHex = CategoryCommands.colors[0]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let form = Binding($editing) {
                    CategoryFormView(form: form)
                        .navigationTitle(form.wrappedValue.id == nil ? "新建分类" : "编辑分类")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = nil } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("保存") { save() }
                                    .disabled(form.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                } else {
                    list
                        .navigationTitle("管理分类")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) }
                            ToolbarItem(placement: .primaryAction) {
                                Button("新建分类", systemImage: "plus") { editing = CategoryForm() }
                            }
                        }
                }
            }
        }
        .frame(width: 480, height: 560)
        .onAppear(perform: reload)
        .confirmationDialog("删除分类「\(pendingDelete?.name ?? "")」？", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { category in
            Button("删除", role: .destructive) { run { try commands.delete(id: category.id) } }
        } message: { _ in
            Text("使用这个分类的任务会变成无分类。启用同步后，删除也会同步到手机。")
        }
    }

    private var list: some View {
        Form {
            Section {
                ForEach(categories) { category in
                    HStack(spacing: 12) {
                        Image(systemName: CategoryIcons.symbol(for: category.iconKey))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color(hexString: category.colorHex) ?? t.primary, in: Circle())
                        Text(category.name)
                        Spacer()
                        Button("编辑") {
                            editing = CategoryForm(id: category.id, name: category.name, iconKey: category.iconKey, colorHex: category.colorHex)
                        }
                        Button("删除", role: .destructive) { pendingDelete = category }
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button("恢复预设分类") { commands.restorePresets(); reload() }
            }
        }
        .formStyle(.grouped)
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

/// 新建 / 编辑分类：名称、颜色、图标。
private struct CategoryFormView: View {
    @Binding var form: CategoryManagerSheet.CategoryForm
    @Environment(\.palette) private var t

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $form.name, prompt: Text("分类名称"))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
            }
            Section("颜色") {
                FlowLayout(spacing: 10) {
                    ForEach(CategoryCommands.colors, id: \.self) { hex in
                        ColorSwatch(hex: hex, selected: form.colorHex.uppercased() == hex) { form.colorHex = hex }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("图标") {
                FlowLayout(spacing: 8) {
                    ForEach(CategoryCommands.iconKeys, id: \.self) { key in
                        let selected = form.iconKey == key
                        let color = Color(hexString: form.colorHex) ?? t.primary
                        Button { form.iconKey = key } label: {
                            Image(systemName: CategoryIcons.symbol(for: key))
                                .font(.body.weight(.medium))
                                .foregroundStyle(selected ? Color.white : t.onSurface)
                                .frame(width: 34, height: 34)
                                .background(selected ? color : t.fieldBg, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}
