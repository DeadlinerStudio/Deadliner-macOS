import SwiftUI

/// Deadliner 的颜色。
///
/// - 页面、分组、文字等表面颜色使用 **系统语义颜色**，跟随 macOS 的深浅色、强调色与对比度设置。
/// - 主色与状态色保持与 Android 一致（深色值取自手机实测）。任务指示色规则来自安卓
///   TaskIndicatorColorFactory：「多彩任务指示标」关闭时，进行中 = Primary、即将到期 = Tertiary、
///   已逾期 = Error、已完成 = Secondary、已放弃 = 灰色；卡片为底色叠加角色色低透明度，进度条为角色色水平渐变。
struct DeadlinerPalette {
    let isDark: Bool
    // 表面（系统语义颜色）
    let pageBg: Color
    let groupBg: Color
    let fieldBg: Color
    let segmentedBg: Color
    let segmentedSelected: Color
    let searchBg: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let cardBase: Color
    // 品牌与状态（与 Android 一致）
    var primary: Color
    let secondary: Color
    let tertiary: Color
    let error: Color
    let abandoned: Color
    var accentFab: Color
    let completedCheck: Color

    private static let surfaces = (
        page: Color(nsColor: .windowBackgroundColor),
        group: Color(nsColor: .controlBackgroundColor),
        field: Color(nsColor: .quaternaryLabelColor).opacity(0.5),
        segmented: Color(nsColor: .quaternaryLabelColor).opacity(0.6),
        segmentedSelected: Color(nsColor: .controlBackgroundColor),
        search: Color(nsColor: .quaternaryLabelColor).opacity(0.5),
        label: Color(nsColor: .labelColor),
        secondaryLabel: Color(nsColor: .secondaryLabelColor)
    )

    static let dark = DeadlinerPalette(
        isDark: true,
        pageBg: surfaces.page, groupBg: surfaces.group, fieldBg: surfaces.field,
        segmentedBg: surfaces.segmented, segmentedSelected: surfaces.segmentedSelected, searchBg: surfaces.search,
        onSurface: surfaces.label, onSurfaceVariant: surfaces.secondaryLabel, cardBase: surfaces.page,
        primary: Color(hex: 0x4078EF), secondary: Color(hex: 0xC0C6DA), tertiary: Color(hex: 0xD9BCDC),
        error: Color(hex: 0xF2B8AE), abandoned: Color(hex: 0x8E8E93), accentFab: Color(hex: 0xD06262),
        completedCheck: Color(hex: 0x8FD3A8)
    )

    static let light = DeadlinerPalette(
        isDark: false,
        pageBg: surfaces.page, groupBg: surfaces.group, fieldBg: surfaces.field,
        segmentedBg: surfaces.segmented, segmentedSelected: surfaces.segmentedSelected, searchBg: surfaces.search,
        onSurface: surfaces.label, onSurfaceVariant: surfaces.secondaryLabel, cardBase: surfaces.group,
        primary: Color(hex: 0x3478F6), secondary: Color(hex: 0x5B6274), tertiary: Color(hex: 0x8B6A8E),
        error: Color(hex: 0xC9443A), abandoned: Color(hex: 0x8E8E93), accentFab: Color(hex: 0xE06A65),
        completedCheck: Color(hex: 0x2E9E5B)
    )

    static func of(_ scheme: ColorScheme, accent: ThemeAccent = .classic) -> DeadlinerPalette {
        var palette = scheme == .dark ? dark : light
        if let color = accent.color {
            palette.primary = color
            palette.accentFab = color
        }
        return palette
    }
}

enum MiuixRadius {
    static let card: CGFloat = 28   // 参照 iOS 版任务卡片（安卓为 24dp）
    static let group: CGFloat = 20
    static let field: CGFloat = 16
    static let dialog: CGFloat = 28
}

enum MiuixCard {
    static let height: CGFloat = 76 // 安卓 DDLItemCardSimplified 高 76dp
    static let padX: CGFloat = 16
    static let padY: CGFloat = 12
    static let gap: CGFloat = 10
    static let minColumnWidth: CGFloat = 340
}

/// 卡片状态色（对应安卓 DeadlineStatusResolver 的五种状态）。
enum IndicatorStatus {
    case undergo, near, passed, completed, abandoned

    struct Colors {
        let indicator: Color
        let indicatorStart: Color
        let overlay: Color
        let base: Color
    }

    func colors(_ t: DeadlinerPalette) -> Colors {
        let (role, indicatorAlpha, backgroundAlpha): (Color, Double, Double) = switch self {
        case .undergo: (t.primary, 0.55, 0.18)
        case .near: (t.tertiary, 0.65, 0.20)
        case .passed: (t.error, 0.65, 0.20)
        case .completed: (t.secondary, 0.65, 0.20)
        case .abandoned: (t.abandoned, 0.65, 0.18)
        }
        return Colors(
            indicator: role.opacity(indicatorAlpha),
            indicatorStart: role.opacity(indicatorAlpha * 0.45),
            overlay: role.opacity(backgroundAlpha),
            base: t.cardBase
        )
    }

    /// 星标使用不透明的角色色。
    func solid(_ t: DeadlinerPalette) -> Color {
        switch self {
        case .undergo: t.primary
        case .near: t.tertiary
        case .passed: t.error
        case .completed: t.secondary
        case .abandoned: t.abandoned
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// 解析 `#RRGGBB`（分类颜色）；格式不对时返回 nil。
    init?(hexString: String) {
        let trimmed = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

private struct DeadlinerPaletteKey: EnvironmentKey {
    static let defaultValue = DeadlinerPalette.light
}

extension EnvironmentValues {
    var palette: DeadlinerPalette {
        get { self[DeadlinerPaletteKey.self] }
        set { self[DeadlinerPaletteKey.self] = newValue }
    }
}

/// 根据深浅色与主题色注入调色板；非「经典」主题时系统控件的强调色也跟随主题。
struct DeadlinerThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(ThemeAccent.storageKey) private var accentRaw = ThemeAccent.classic.rawValue

    func body(content: Content) -> some View {
        let accent = ThemeAccent(rawValue: accentRaw) ?? .classic
        content
            .environment(\.palette, .of(scheme, accent: accent))
            .tint(accent.color)
    }
}

extension View {
    func deadlinerTheme() -> some View { modifier(DeadlinerThemeModifier()) }
}
