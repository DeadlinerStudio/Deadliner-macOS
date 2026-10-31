import SwiftUI

/// 页面顶部的氛围光（对应 Android ModernSemanticAtmosphere / iOS 顶部氛围）：
/// 一层随页面语义变色的柔和渐变，向下自然淡出。
///
/// 淡出的尾部完全落在视图自身的高度内，避免被父视图裁切而出现横向断层。
struct TopAtmosphere: View {
    let tone: Color
    var height: CGFloat = 300
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 0.32 : 0.18
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: tone.opacity(strength), location: 0),
                    .init(color: tone.opacity(strength * 0.45), location: 0.45),
                    .init(color: tone.opacity(0), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            // 两团偏移的光斑，让颜色不那么平。
            RadialGradient(colors: [tone.opacity(strength * 0.9), .clear], center: .init(x: 0.15, y: 0), startRadius: 0, endRadius: height * 0.9)
            RadialGradient(colors: [tone.opacity(strength * 0.6), .clear], center: .init(x: 0.85, y: 0.1), startRadius: 0, endRadius: height * 0.7)
        }
        .frame(height: height)
        .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.24), value: tone)
    }
}

extension View {
    /// 在页面顶部铺一层氛围光。
    func topAtmosphere(_ tone: Color) -> some View {
        background(alignment: .top) { TopAtmosphere(tone: tone).ignoresSafeArea(edges: .top) }
    }
}
