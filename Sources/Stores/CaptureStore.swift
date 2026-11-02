import Foundation
import Observation
import Shared

/// 灵感（Capture）：与 iOS 端相同，直接读写 Core 的 `CaptureRepository`（随同步到各端）。
/// Core 的 `CaptureViewModel` 需要 Kotlin 协程作用域，Swift 无法构造，因此合并按它的规则实现：
/// 按创建时间排序、去掉首尾空白，用 `\n\n---\n\n` 连接，新建一条后删除原来的几条。
@MainActor
@Observable
final class CaptureStore {
    struct Idea: Identifiable, Equatable {
        let id: String
        var text: String
        var createdAt: Date?
        var updatedAt: Date?
    }

    private(set) var items: [Idea] = []
    var searchText = ""

    /// 与 Core `CaptureViewModel` 相同的合并分隔符。
    static let mergeSeparator = "\n\n---\n\n"

    @ObservationIgnored private let database: DeadlinerDatabase
    @ObservationIgnored private let didChange: () -> Void

    init(database: DeadlinerDatabase, didChange: @escaping () -> Void = {}) {
        self.database = database
        self.didChange = didChange
    }

    var visibleItems: [Idea] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? items : items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    /// 未整理、未删除的灵感，新的在前。
    func refresh() {
        items = database.captures.listUnconsumed()
            .filter { !$0.isDeleted }
            .map { Idea(id: $0.uid, text: $0.text, createdAt: CoreDates.parseInstant($0.createdAt), updatedAt: CoreDates.parseInstant($0.updatedAt)) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    @discardableResult
    func create(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = CoreClock.now()
        let uid = PlatformIdentity.shared.doNewId()
        database.captures.create(item: CaptureItem(uid: uid, text: trimmed, source: CaptureSource.manual, createdAt: now,
                                                   updatedAt: now, isConsumed: false, isDeleted: false))
        changed()
        return uid
    }

    func update(_ id: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let item = database.captures.find(uid: id) else { return }
        database.captures.update(item: item.doCopy(uid: item.uid, text: trimmed, source: item.source, createdAt: item.createdAt,
                                                   updatedAt: CoreClock.now(), isConsumed: item.isConsumed, isDeleted: item.isDeleted))
        changed()
    }

    func delete(_ ids: [String]) {
        let now = CoreClock.now()
        ids.forEach { database.captures.delete(uid: $0, updatedAt: now) }
        changed()
    }

    /// 整理成任务或习惯后标记为已整理，从列表中移除（与 Core `markConsumed` 相同）。
    func markConsumed(_ id: String) {
        guard let item = database.captures.find(uid: id) else { return }
        database.captures.update(item: item.doCopy(uid: item.uid, text: item.text, source: item.source, createdAt: item.createdAt,
                                                   updatedAt: CoreClock.now(), isConsumed: true, isDeleted: item.isDeleted))
        changed()
    }

    /// 合并选中的灵感，返回新灵感的 ID 和文字。只选一条时不合并，直接返回它。
    func merge(_ ids: Set<String>) -> (id: String, text: String)? {
        let selected = items.filter { ids.contains($0.id) }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        guard let first = selected.first else { return nil }
        if selected.count == 1 { return (first.id, first.text) }
        let text = selected.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: Self.mergeSeparator)
        guard let uid = create(text) else { return nil }
        delete(selected.map(\.id))
        return (uid, text)
    }

    /// 把灵感拆成标题（第一行，最多 60 个字）和备注（其余部分），用于预填编辑器。
    static func titleAndNote(_ text: String) -> (title: String, note: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let firstIndex = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "---" } ?? 0
        let first = lines.isEmpty ? "" : lines[firstIndex].trimmingCharacters(in: .whitespaces)
        let title = first.count > 60 ? String(first.prefix(60)) : first
        var rest = lines
        if !rest.isEmpty { rest.remove(at: firstIndex) }
        var note = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if first.count > 60 { note = (String(first.dropFirst(60)) + (note.isEmpty ? "" : "\n" + note)) }
        return (title, note)
    }

    private func changed() {
        refresh()
        didChange()
    }
}
