import SwiftUI

/// 状态色对齐 iOS DDLStatusStyle；表面使用 macOS 系统语义颜色。
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
    // 品牌与状态（与 iOS 一致）
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
        primary: .blue, secondary: .green, tertiary: .orange,
        error: .red, abandoned: .gray, accentFab: Color(hex: 0xFF6D6D),
        completedCheck: .green
    )

    static let light = DeadlinerPalette(
        isDark: false,
        pageBg: surfaces.page, groupBg: surfaces.group, fieldBg: surfaces.field,
        segmentedBg: surfaces.segmented, segmentedSelected: surfaces.segmentedSelected, searchBg: surfaces.search,
        onSurface: surfaces.label, onSurfaceVariant: surfaces.secondaryLabel, cardBase: surfaces.group,
        primary: .blue, secondary: .green, tertiary: .orange,
        error: .red, abandoned: .gray, accentFab: Color(hex: 0xFF6D6D),
        completedCheck: .green
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

/// 卡片状态色与透明度对应 iOS DDLStatusStyle。
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
