import AppKit

// 生成应用图标（1024×1024，不透明）：OSVIA 设计包的图标。
// 深灰黑底 #0B0F14；荷绿 #00E5A8 开口向右的圆环（外径 245、线宽 33、开口 ±35°，平头）；中心白点 #F5F7FA 半径 44.5。
// 与 Shared/BrandMark.swift 里的比例一致。
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let S = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

// 背景
ctx.setFillColor(CGColor(red: 11.0 / 255, green: 15.0 / 255, blue: 20.0 / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// 圆环：中心线半径 = (245 + 212) / 2，线宽 33。CGContext 是 y 向上，逆时针从 35° 经左侧走到 325°
let center = CGPoint(x: S / 2, y: S / 2)
ctx.setStrokeColor(CGColor(red: 0, green: 229.0 / 255, blue: 168.0 / 255, alpha: 1))
ctx.setLineWidth(33)
ctx.setLineCap(.butt)
ctx.addArc(center: center, radius: 228.5, startAngle: 35 * CGFloat.pi / 180, endAngle: 325 * CGFloat.pi / 180, clockwise: false)
ctx.strokePath()

// 中心白点
ctx.setFillColor(CGColor(red: 245.0 / 255, green: 247.0 / 255, blue: 250.0 / 255, alpha: 1))
ctx.fillEllipse(in: CGRect(x: center.x - 44.5, y: center.y - 44.5, width: 89, height: 89))

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: out))
print("icon written to \(out)")
