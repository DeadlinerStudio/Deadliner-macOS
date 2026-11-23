import SwiftUI

/// 显示大小（与安卓「显示大小」对应）：整体缩放主窗口的侧栏和页面内容。
/// macOS 的 SwiftUI 不跟随动态字体，所以按比例缩放整个内容：缩放前把可用空间按比例换算，
/// 缩放后正好铺满窗口；文字和控件都会重新排版，不会出现横向滚动。
enum DisplayScale: String, CaseIterable, Identifiable {
    case compact, slightlyCompact, standard, slightlyLarge, large

    static let storageKey = "display.scale"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: String(localized: "更紧凑")
        case .slightlyCompact: String(localized: "稍紧凑")
        case .standard: String(localized: "标准")
        case .slightlyLarge: String(localized: "稍大")
        case .large: String(localized: "更大")
        }
    }

    var factor: CGFloat {
        switch self {
        case .compact: 0.85
        case .slightlyCompact: 0.92
        case .standard: 1
        case .slightlyLarge: 1.1
        case .large: 1.2
        }
    }
}

private struct DisplayScaleModifier: ViewModifier {
    @AppStorage(DisplayScale.storageKey) private var raw = DisplayScale.standard.rawValue

    func body(content: Content) -> some View {
        let factor = (DisplayScale(rawValue: raw) ?? .standard).factor
        if factor == 1 {
            content
        } else {
            GeometryReader { proxy in
                content
                    .frame(width: proxy.size.width / factor, height: proxy.size.height / factor)
                    .scaleEffect(factor, anchor: .topLeading)
            }
        }
    }
}

extension View {
    /// 按设置中的「显示大小」缩放。
    func displayScaled() -> some View { modifier(DisplayScaleModifier()) }
}
