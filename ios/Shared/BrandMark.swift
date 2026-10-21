import SwiftUI

// OSVIA 品牌标志：开口向右的薄荷绿圆环（搜索·思考·行动的「C」）+ 中心一颗白点，底色深灰黑。
// 几何量自设计包的 1024 图标：圆环外径 245、线宽 33、开口 ±35°、白点半径 44.5。
// 应用图标脚本 tools/make_icon.swift 使用同一组数据，改这里要同步改那里。
enum BrandPalette {
    static let bg = Color(red: 11 / 255, green: 15 / 255, blue: 20 / 255)        // #0B0F14
    static let mint = Color(red: 0, green: 229 / 255, blue: 168 / 255)            // #00E5A8
    static let ink = Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255)     // #F5F7FA
    static let sub = Color(red: 164 / 255, green: 170 / 255, blue: 168 / 255)     // #A4AAA8
    static let panel = Color(red: 15 / 255, green: 21 / 255, blue: 26 / 255)      // #0F151A
    static let bubble = Color(red: 22 / 255, green: 29 / 255, blue: 35 / 255)     // #161D23
    static let line = Color(red: 39 / 255, green: 48 / 255, blue: 47 / 255)       // #27302F
}

// 仅图形（无底色）：size = 圆环外径。灵动岛、分享图等深色背景上直接使用
struct BrandGlyph: View {
    var size: CGFloat = 64
    var dot = true
    var weight: CGFloat = 0.0673   // 线宽占 size 的比例（思考状态图标用更粗的）

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 35.0 / 360.0, to: 325.0 / 360.0)
                .stroke(BrandPalette.mint, style: StrokeStyle(lineWidth: size * weight, lineCap: .butt))
                .frame(width: size * 0.9327, height: size * 0.9327)
            if dot {
                Circle()
                    .fill(BrandPalette.ink)
                    .frame(width: size * 0.1816, height: size * 0.1816)
            }
        }
        .frame(width: size, height: size)
    }
}

// 带圆角底色的完整标志（应用内使用；桌面图标由脚本生成，系统自己裁圆角）
struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(BrandPalette.bg)
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(BrandPalette.line, lineWidth: 0.5)
            BrandGlyph(size: size * 0.4785)
        }
        .frame(width: size, height: size)
    }
}
