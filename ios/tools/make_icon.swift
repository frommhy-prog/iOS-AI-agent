import AppKit

// 生成应用图标（1024×1024，不透明）：深海军蓝底 + TSTZ 字母 + 金色点缀
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

// 背景渐变
let colors = [CGColor(red: 0.06, green: 0.14, blue: 0.32, alpha: 1), CGColor(red: 0.01, green: 0.04, blue: 0.13, alpha: 1)] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// 金色细弧装饰
ctx.setStrokeColor(CGColor(red: 0.93, green: 0.74, blue: 0.36, alpha: 0.35))
ctx.setLineWidth(10)
ctx.addArc(center: CGPoint(x: 512, y: 512), radius: 430, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
ctx.strokePath()

let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gc

let font = NSFont.systemFont(ofSize: 400, weight: .black)
func letter(_ s: String, cx: CGFloat, cy: CGFloat, color: NSColor) {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let w = a.size().width
    let y = cy - font.capHeight / 2 + font.descender
    a.draw(at: NSPoint(x: cx - w / 2, y: y))
}
let white = NSColor.white
let gold = NSColor(red: 0.93, green: 0.74, blue: 0.36, alpha: 1)
letter("T", cx: 330, cy: 690, color: white)
letter("S", cx: 694, cy: 690, color: white)
letter("T", cx: 330, cy: 340, color: white)
letter("Z", cx: 694, cy: 340, color: gold)

NSGraphicsContext.restoreGraphicsState()

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: out))
print("icon written to \(out)")
