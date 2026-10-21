import SwiftUI

// 品牌标志「知行」：深海蓝底 + 白色 Z 形折线一笔到底，末端金色箭头（知 → 行），起点一颗金色光点。
// 应用图标脚本 tools/make_icon.swift 使用同一套坐标，改这里要同步改那里。
enum BrandPalette {
    static let gold = Color(red: 0.93, green: 0.74, blue: 0.36)
    static let navTop = Color(red: 0.06, green: 0.14, blue: 0.32)
    static let navBottom = Color(red: 0.01, green: 0.04, blue: 0.13)
}

private func unit(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

// 仅图形（无底色），灵动岛等深色背景上直接使用
struct BrandGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        let style = StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round)
        let s = size
        ZStack {
            Path { p in
                p.move(to: unit(0.25, 0.25, s))
                p.addLine(to: unit(0.73, 0.25, s))
                p.addLine(to: unit(0.25, 0.69, s))
                p.addLine(to: unit(0.77, 0.69, s))
            }
            .stroke(Color.white, style: style)
            Path { p in
                p.move(to: unit(0.65, 0.57, s))
                p.addLine(to: unit(0.78, 0.69, s))
                p.addLine(to: unit(0.65, 0.81, s))
            }
            .stroke(BrandPalette.gold, style: style)
            Circle()
                .fill(BrandPalette.gold)
                .frame(width: size * 0.13, height: size * 0.13)
                .position(unit(0.25, 0.25, s))
        }
        .frame(width: size, height: size)
    }
}

// 带圆角底色的完整标志
struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [BrandPalette.navTop, BrandPalette.navBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            BrandGlyph(size: size)
        }
        .frame(width: size, height: size)
    }
}
