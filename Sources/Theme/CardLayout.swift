import SwiftUI

/// 卡片列表的显示模式：列数固定，不随窗口宽度变化（任务页工具栏可切换，习惯与归档沿用同一设置）。
enum CardLayout: String, CaseIterable, Identifiable {
    case single, double, triple

    static let storageKey = "cards.layout"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "单列"
        case .double: "双列"
        case .triple: "三列"
        }
    }

    var systemImage: String {
        switch self {
        case .single: "rectangle.grid.1x2"
        case .double: "square.grid.2x2"
        case .triple: "square.grid.3x2"
        }
    }

    var columnCount: Int {
        switch self {
        case .single: 1
        case .double: 2
        case .triple: 3
        }
    }

    /// 内容最大宽度：单列时避免卡片在宽屏上被拉得过长。
    var maxContentWidth: CGFloat {
        switch self {
        case .single: 760
        case .double: 1320
        case .triple: 1800
        }
    }

    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: MiuixCard.gap), count: columnCount)
    }
}

extension View {
    /// 限制内容宽度并在可用空间中居中。
    func readableWidth(_ width: CGFloat) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}
