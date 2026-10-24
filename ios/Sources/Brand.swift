import SwiftUI
import UIKit

// 统一的外观：按 OSVIA 设计包的配色。
// 深色：深灰黑底 #0B0F14、荷绿强调 #00E5A8；浅色：偏冷的中性浅灰（不再泛黄）、黑色强调。
enum Brand {
    // 应用名 OSVIA，品牌语「Search · Think · Act」
    static let name = "OSVIA"
    static let tagline = "搜索 · 思考 · 行动"

    private static func hex(_ v: Int) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private static func dyn(_ light: Int, _ dark: Int) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? hex(dark) : hex(light) })
    }

    // 强调色：浅色模式为黑，深色模式为荷绿；放在它上面的文字用 onAccent
    static let accent = dyn(0x0B0F14, 0x00E5A8)
    static let onAccent = dyn(0xFFFFFF, 0x0B0F14)
    static let bg = dyn(0xF4F6F8, 0x0B0F14)
    static let card = dyn(0xFFFFFF, 0x131A20)
    static let userBubble = dyn(0xE6EAEE, 0x1B242C)
    static let codeBg = dyn(0xECEFF2, 0x0F151A)
    static let line = dyn(0xDCE1E6, 0x27302F)
    static let ink = dyn(0x0B0F14, 0xF5F7FA)
    static let sub = dyn(0x68717A, 0xA4AAA8)
    static let serif = Font.system(size: 17, design: .serif)
}
