import AppKit
import SwiftUI

/// 自定义的任务状态色：只保存在本机（不同步），格式为 `undergo=#RRGGBB;near=#RRGGBB`。
enum StatusColorSettings {
    static let storageKey = "task.statusColors"

    static func decode(_ raw: String) -> [IndicatorStatus: Color] {
        var result: [IndicatorStatus: Color] = [:]
        for pair in raw.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let status = IndicatorStatus(rawValue: parts[0]),
                  let color = Color(hexString: parts[1]) else { continue }
            result[status] = color
        }
        return result
    }

    /// 设置或清除（`nil`）某个状态的颜色，返回新的保存值。
    static func updating(_ raw: String, _ status: IndicatorStatus, to color: Color?) -> String {
        var hexes: [IndicatorStatus: String] = [:]
        for (key, value) in decode(raw) { hexes[key] = hex(value) }
        hexes[status] = color.map(hex)
        return IndicatorStatus.allCases.compactMap { s in hexes[s].map { "\(s.rawValue)=\($0)" } }.joined(separator: ";")
    }

    static func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
