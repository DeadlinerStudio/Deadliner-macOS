import Foundation

/// 界面语言（跟随系统，可在「系统设置 → 通用 → 语言与地区 → 应用程序」中为 Deadliner 单独选择）。
/// 日期格式化与星期名称按界面语言显示，避免中文界面里出现英文日期，或英文界面里出现中文日期。
enum AppLanguage {
    static var identifier: String { Bundle.main.preferredLocalizations.first ?? "zh-Hans" }
    static var isEnglish: Bool { identifier.hasPrefix("en") }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "zh_CN") }

    /// 列举时的分隔符：中文用顿号，英文用逗号。
    static var listSeparator: String { isEnglish ? ", " : "、" }

    /// 从周一开始的星期名称。`style` 为 .narrow 时是日历表头用的单字（一 / M），为 .short 时是「周一 / Mon」。
    static func weekdays(_ style: Style = .narrow) -> [String] {
        let f = DateFormatter()
        f.locale = locale
        let symbols: [String]
        switch style {
        case .narrow: symbols = isEnglish ? (f.veryShortStandaloneWeekdaySymbols ?? []) : ["日", "一", "二", "三", "四", "五", "六"]
        case .short: symbols = f.shortStandaloneWeekdaySymbols ?? []
        }
        guard symbols.count == 7 else { return [] }
        return Array(symbols[1...]) + [symbols[0]]
    }

    enum Style { case narrow, short }
}
