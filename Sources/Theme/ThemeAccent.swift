import SwiftUI

/// 主题色。名称与取色参照 iOS 版的主题选项（只参考取值，代码独立实现）。
/// 「经典」保留与手机一致的主色与珊瑚色「+」；其他主题的主色、「+」与系统控件强调色都跟随主题。
enum ThemeAccent: String, CaseIterable, Identifiable {
    case classic, cool, blue, brown, cyan, gray, green, indigo, mint, orange, pink, purple, red, teal, yellow

    static let storageKey = "theme.accent"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: "经典"
        case .cool: "冷调"
        case .blue: "晴空"
        case .brown: "琥珀"
        case .cyan: "冰川"
        case .gray: "雾灰"
        case .green: "森屿"
        case .indigo: "深海"
        case .mint: "薄荷"
        case .orange: "落日"
        case .pink: "樱语"
        case .purple: "暮紫"
        case .red: "绯红"
        case .teal: "潮汐"
        case .yellow: "晨光"
        }
    }

    /// 主色；为 nil 时（经典）使用调色板里与手机一致的主色。
    var color: Color? {
        switch self {
        case .classic: nil
        case .cool: Color(hex: 0x7F9CB9)
        case .blue: .blue
        case .brown: .brown
        case .cyan: .cyan
        case .gray: .gray
        case .green: .green
        case .indigo: .indigo
        case .mint: .mint
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .teal: .teal
        case .yellow: .yellow
        }
    }

    /// 「幻彩」浮光的三种颜色。
    var glowColors: [Color] {
        let hex: [UInt32] = switch self {
        case .classic: [0x6AA9FF, 0xFF6AE6, 0xFFC36A]
        case .cool: [0x7F9CB9, 0x8DAECF, 0xB7CCD9]
        case .blue: [0x7B8CFF, 0x6FD3FF, 0xA5C8FF]
        case .brown: [0xB07D52, 0xD59A73, 0xF4C58C]
        case .cyan: [0x78E7FF, 0xA5FFF4, 0x8FD8FF]
        case .gray: [0x94A3B8, 0xC0CAD6, 0xE2E8F0]
        case .green: [0x6EE7B7, 0xB7F27D, 0x8EEBC4]
        case .indigo: [0x8B7CFF, 0x6AC7FF, 0xA99CFF]
        case .mint: [0x83F7D5, 0xC6FFE4, 0x9DF2E0]
        case .orange: [0xFF8A65, 0xFFD36E, 0xFFAF7A]
        case .pink: [0xFF8AD8, 0xFFC38F, 0xFFA6E2]
        case .purple: [0xD28BFF, 0x8FA8FF, 0xC3A1FF]
        case .red: [0xFF7A8A, 0xFFB86A, 0xFF9C9C]
        case .teal: [0x66E3D7, 0xA6FFF1, 0x7FD9E8]
        case .yellow: [0xFFD95A, 0xFFF1A8, 0xFFE27F]
        }
        return hex.map { Color(hex: $0) }
    }
}

/// 顶部浮光风格（对应 iOS 的「沉浸」「幻彩」，另加关闭）。
enum GlowStyle: String, CaseIterable, Identifiable {
    case immersive, vivid, off

    static let storageKey = "theme.glowStyle"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .immersive: "沉浸"
        case .vivid: "幻彩"
        case .off: "关闭"
        }
    }
}
