import SwiftUI

struct CLITaskDraft: Identifiable {
    let id: String
    let original: CLITaskSnapshot.Row?
    var title, note, startAt, dueAt: String

    init(_ row: CLITaskSnapshot.Row? = nil) {
        id = row?.uid ?? UUID().uuidString
        original = row
        title = row?.title ?? ""
        note = row?.note ?? ""
        startAt = row?.startAt ?? ""
        dueAt = row?.dueAt ?? ""
    }

    var fields: [String: String?] {
        var result: [String: String?] = [:]
        if title != original?.title { result["title"] = title }
        if note != (original?.note ?? "") { result["note"] = note }
        for (key, value, old) in [("startAt", startAt, original?.startAt), ("dueAt", dueAt, original?.dueAt)] {
            if value != (old ?? "") { result.updateValue(value.isEmpty ? nil : value, forKey: key) }
        }
        return result
    }
}

struct CLITaskEditor: View {
    @State var draft: CLITaskDraft
    let latest: CLITaskSnapshot.Row?
    let save: (CLITaskDraft) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.original == nil ? "新建 CLI 任务" : "编辑 CLI 任务").font(.title2)
            Form {
                TextField("标题", text: $draft.title)
                TextField("备注", text: $draft.note, axis: .vertical)
                TextField("开始时间", text: $draft.startAt)
                TextField("截止时间", text: $draft.dueAt)
            }
            .disabled(saving)
            Text("时间可留空，或填写带时区的时间，如 2026-11-23T18:30:00+08:00。").font(.caption)
            if !error.isEmpty { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let latest, let original = draft.original, latest.updatedAt != original.updatedAt {
                Button("放弃草稿并载入最新版本") { draft = CLITaskDraft(latest); error = "" }
                    .disabled(saving)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button("保存") {
                    saving = true
                    Task {
                        do { try await save(draft); dismiss() }
                        catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.fields.isEmpty)
            }
        }.padding(24).frame(minWidth: 440).interactiveDismissDisabled(saving)
    }
}
