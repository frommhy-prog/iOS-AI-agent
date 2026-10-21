import AppKit

// 生成应用图标（1024×1024，不透明）：深海蓝底 + 白色 Z 形折线一笔到底 + 金色箭头与起点光点。
// 坐标与 Shared/BrandMark.swift 完全一致（0~1 的相对坐标，y 向下），改动要两边同步。
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let S = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * S, y: (1 - y) * S) }

// 背景渐变
let colors = [CGColor(red: 0.06, green: 0.14, blue: 0.32, alpha: 1), CGColor(red: 0.01, green: 0.04, blue: 0.13, alpha: 1)] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

ctx.setLineWidth(S * 0.085)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Z 形折线（白）
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.move(to: P(0.25, 0.25))
ctx.addLine(to: P(0.73, 0.25))
ctx.addLine(to: P(0.25, 0.69))
ctx.addLine(to: P(0.77, 0.69))
ctx.strokePath()

// 箭头（金）
let gold = CGColor(red: 0.93, green: 0.74, blue: 0.36, alpha: 1)
ctx.setStrokeColor(gold)
ctx.move(to: P(0.65, 0.57))
ctx.addLine(to: P(0.78, 0.69))
ctx.addLine(to: P(0.65, 0.81))
ctx.strokePath()

// 起点光点（金）
ctx.setFillColor(gold)
let c = P(0.25, 0.25)
let r = S * 0.065
ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: out))
print("icon written to \(out)")
