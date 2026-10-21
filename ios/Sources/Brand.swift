import SwiftUI
import UIKit

// 统一的外观：暖色背景，强调色随系统深浅色变为黑或白（不再使用彩色主题）。主题只保留「跟随系统 / 浅色 / 深色」。
enum Brand {
    // 应用名：「知行」= 知（知识库、理解）+ 行（闹钟、任务、脚本、转换，说到做到）
    static let name = "知行"
    static let tagline = "会成长的口袋助理"

    private static func hex(_ v: Int) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private static func dyn(_ light: Int, _ dark: Int) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? hex(dark) : hex(light) })
    }

    // 强调色：浅色模式为黑，深色模式为白；放在它上面的文字用 onAccent
    static let accent = dyn(0x1F1E1D, 0xF2F0E9)
    static let onAccent = dyn(0xFFFFFF, 0x1F1E1D)
    static let bg = dyn(0xF5F4EE, 0x262624)
    static let card = dyn(0xFFFFFF, 0x30302E)
    static let userBubble = dyn(0xE9E6DB, 0x3A3A37)
    static let codeBg = dyn(0xEDEBE3, 0x1F1E1D)
    static let line = dyn(0xE0DDD2, 0x45443F)
    static let ink = dyn(0x1F1E1D, 0xF2F0E9)
    static let sub = dyn(0x7B786F, 0xA19E94)
    static let serif = Font.system(size: 17, design: .serif)
}
