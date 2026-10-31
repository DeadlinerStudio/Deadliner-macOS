import SwiftUI

/// MIUIX 设计参数（对齐安卓 Deadliner v6「MIUIX / HyperOS」设计模式）。
///
/// 深色值取自手机实测截图；任务指示色规则来自安卓 TaskIndicatorColorFactory：
/// 「多彩任务指示标」关闭时，进行中 = Primary、即将到期 = Tertiary、已逾期 = Error、
/// 已完成 = Secondary、已放弃 = 灰色；底色为纯白 / 纯黑叠加角色色低透明度，
/// 进度条为角色色水平渐变。
struct MiuixTokens {
    let isDark: Bool
    let pageBg: Color
    let groupBg: Color
    let fieldBg: Color
    let segmentedBg: Color
    let segmentedSelected: Color
    let searchBg: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let cardBase: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let error: Color
    let abandoned: Color
    let accentFab: Color
    let completedCheck: Color

    static let dark = MiuixTokens(
        isDark: true,
        pageBg: Color(hex: 0x000000), groupBg: Color(hex: 0x202022), fieldBg: Color(hex: 0x2B2B2D),
        segmentedBg: Color(hex: 0x2A2A2C), segmentedSelected: Color(hex: 0x4A4A4D), searchBg: Color(hex: 0x2C2C2E),
        onSurface: Color(hex: 0xECECEC), onSurfaceVariant: Color(hex: 0xA0A0A6), cardBase: Color(hex: 0x000000),
        primary: Color(hex: 0x4078EF), secondary: Color(hex: 0xC0C6DA), tertiary: Color(hex: 0xD9BCDC),
        error: Color(hex: 0xF2B8AE), abandoned: Color(hex: 0x8E8E93), accentFab: Color(hex: 0xD06262),
        completedCheck: Color(hex: 0x8FD3A8)
    )

    static let light = MiuixTokens(
        isDark: false,
        pageBg: Color(hex: 0xF7F7F7), groupBg: Color(hex: 0xFFFFFF), fieldBg: Color(hex: 0xF0F0F2),
        segmentedBg: Color(hex: 0xEBEBED), segmentedSelected: Color(hex: 0xFFFFFF), searchBg: Color(hex: 0xEBEBED),
        onSurface: Color(hex: 0x1A1A1C), onSurfaceVariant: Color(hex: 0x6E6E73), cardBase: Color(hex: 0xFFFFFF),
        primary: Color(hex: 0x3478F6), secondary: Color(hex: 0x5B6274), tertiary: Color(hex: 0x8B6A8E),
        error: Color(hex: 0xC9443A), abandoned: Color(hex: 0x8E8E93), accentFab: Color(hex: 0xE06A65),
        completedCheck: Color(hex: 0x2E9E5B)
    )

    static func of(_ scheme: ColorScheme) -> MiuixTokens { scheme == .dark ? dark : light }
}

enum MiuixRadius {
    static let card: CGFloat = 24   // 安卓 item_corner_radius = 24dp
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

    func colors(_ t: MiuixTokens) -> Colors {
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
    func solid(_ t: MiuixTokens) -> Color {
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

private struct MiuixTokensKey: EnvironmentKey {
    static let defaultValue = MiuixTokens.light
}

extension EnvironmentValues {
    var miuix: MiuixTokens {
        get { self[MiuixTokensKey.self] }
        set { self[MiuixTokensKey.self] = newValue }
    }
}

/// 根据当前深浅色注入 MIUIX 参数。
struct MiuixThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.environment(\.miuix, .of(scheme))
    }
}

extension View {
    func miuixTheme() -> some View { modifier(MiuixThemeModifier()) }
}
