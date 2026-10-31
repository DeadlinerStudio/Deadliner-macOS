import SwiftUI

/// 玻璃效果兼容层：macOS 26 及以上使用系统 Liquid Glass，macOS 14～25 退回系统毛玻璃。
/// 只用于浮在内容之上的元素（「+」按钮、悬停操作、选中的日期等）；卡片本身保持色块，不做成玻璃。
private struct LegacyGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 为 true 时即使在 macOS 26 上也使用毛玻璃（截图测试用来检查旧系统外观）。
    var forceLegacyGlass: Bool {
        get { self[LegacyGlassKey.self] }
        set { self[LegacyGlassKey.self] = newValue }
    }
}

private struct DeadlinerGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.forceLegacyGlass) private var forceLegacy

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !forceLegacy {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background {
                    shape.fill(.regularMaterial)
                    if let tint { shape.fill(tint.opacity(0.85)) }
                }
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
    }
}

extension View {
    /// Deadliner 的玻璃效果。`tint` 为玻璃着色（例如珊瑚色「+」），`interactive` 用于可点击的元素。
    func deadlinerGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(DeadlinerGlass(shape: shape, tint: tint, interactive: interactive))
    }
}
