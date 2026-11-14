import SwiftUI

/// 完成任务时的彩带动画（与安卓「完成时显示动画效果」对应）。只在这台 Mac 上设置。
enum CelebrationSettings {
    static let enabledKey = "celebration.enabled"
    static let duration: TimeInterval = 1.8
}

/// 彩带：从窗口顶部两侧喷出、受重力下落并淡出。不接收点击，开启「减少动态效果」时不播放。
struct CelebrationOverlay: View {
    /// 每次加 1 播放一次。
    let trigger: Int
    @AppStorage(CelebrationSettings.enabledKey) private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: Burst?

    struct Particle {
        var x: Double, y: Double, vx: Double, vy: Double
        var spin: Double, size: Double, color: Color, isCircle: Bool
    }

    struct Burst {
        let start: Date
        let particles: [Particle]
    }

    var body: some View {
        Group {
            if let burst {
                TimelineView(.animation) { context in
                    Canvas { canvas, size in
                        Self.draw(burst, at: context.date.timeIntervalSince(burst.start), in: &canvas, size: size)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard enabled, !reduceMotion else { return }
            let next = Burst(start: Date(), particles: Self.makeParticles())
            burst = next
            DispatchQueue.main.asyncAfter(deadline: .now() + CelebrationSettings.duration) {
                if burst?.start == next.start { burst = nil }
            }
        }
    }

    static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .indigo, .pink, .purple]

    /// 位置以窗口宽高的比例表示，速度为每秒的比例。
    static func makeParticles(count: Int = 90) -> [Particle] {
        (0..<count).map { index in
            let left = index % 2 == 0
            return Particle(
                x: left ? 0.05 : 0.95, y: 0.02,
                vx: (left ? 1 : -1) * Double.random(in: 0.15...0.65),
                vy: Double.random(in: -0.15...0.35),
                spin: Double.random(in: -8...8), size: Double.random(in: 5...10),
                color: colors.randomElement()!, isCircle: Bool.random()
            )
        }
    }

    static func draw(_ burst: Burst, at t: Double, in canvas: inout GraphicsContext, size: CGSize) {
        guard t >= 0, t < CelebrationSettings.duration else { return }
        let gravity = 0.9
        let fade = max(0, min(1, (CelebrationSettings.duration - t) / 0.6))
        for p in burst.particles {
            let x = (p.x + p.vx * t) * size.width
            let y = (p.y + p.vy * t + 0.5 * gravity * t * t) * size.height
            guard y < size.height + 20 else { continue }
            var item = canvas
            item.opacity = fade
            item.translateBy(x: x, y: y)
            item.rotate(by: .radians(p.spin * t))
            let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.isCircle ? p.size : p.size / 2)
            item.fill(p.isCircle ? Path(ellipseIn: rect) : Path(rect), with: .color(p.color))
        }
    }
}
