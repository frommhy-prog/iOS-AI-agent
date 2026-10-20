import SwiftUI
import UIKit

// 轻量 Markdown 渲染：标题、列表、引用、代码块（可复制）、粗体斜体行内样式。流式输出时每次重新解析，未闭合的代码块也能正常显示。
enum MDBlock {
    case para(String)
    case heading(Int, String)
    case bullet(String, String)
    case quote(String)
    case code(String, String)
    case rule
}

enum MD {
    static func parse(_ s: String) -> [MDBlock] {
        var out: [MDBlock] = []
        var para: [String] = []
        var inCode = false
        var lang = ""
        var code: [String] = []
        func flush() {
            if !para.isEmpty {
                out.append(.para(para.joined(separator: "\n")))
                para = []
            }
        }
        for line in s.components(separatedBy: "\n") {
            let tr = line.trimmingCharacters(in: .whitespaces)
            if inCode {
                if tr.hasPrefix("```") {
                    out.append(.code(lang, code.joined(separator: "\n")))
                    code = []
                    inCode = false
                } else {
                    code.append(line)
                }
                continue
            }
            if tr.hasPrefix("```") {
                flush()
                inCode = true
                lang = String(tr.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if tr.isEmpty { flush(); continue }
            if let h = heading(tr) { flush(); out.append(h); continue }
            if tr == "---" || tr == "***" { flush(); out.append(.rule); continue }
            if tr.hasPrefix(">") {
                flush()
                out.append(.quote(String(tr.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let b = bullet(tr) { flush(); out.append(b); continue }
            para.append(line)
        }
        if inCode { out.append(.code(lang, code.joined(separator: "\n"))) }
        flush()
        return out
    }

    private static func heading(_ t: String) -> MDBlock? {
        var n = 0
        for c in t {
            if c == "#" { n += 1 } else { break }
        }
        guard n >= 1, n <= 6, t.dropFirst(n).first == " " else { return nil }
        return .heading(n, String(t.dropFirst(n + 1)))
    }

    private static func bullet(_ t: String) -> MDBlock? {
        for p in ["- ", "* ", "• ", "+ "] where t.hasPrefix(p) {
            return .bullet("•", String(t.dropFirst(p.count)))
        }
        if let r = t.range(of: "^\\d+[.)、]\\s+", options: .regularExpression) {
            let marker = t[r].trimmingCharacters(in: .whitespaces)
            return .bullet(marker, String(t[r.upperBound...]))
        }
        return nil
    }

    static func attr(_ s: String) -> AttributedString {
        let o = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: o)) ?? AttributedString(s)
    }
}

struct MarkdownText: View {
    let text: String

    var body: some View {
        let blocks = MD.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { i in MDBlockView(block: blocks[i]) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct MDBlockView: View {
    let block: MDBlock
    @State private var copied = false

    var body: some View {
        switch block {
        case .para(let s):
            Text(MD.attr(s)).font(Brand.serif).lineSpacing(5).foregroundStyle(Brand.ink)
        case .heading(let n, let s):
            Text(MD.attr(s))
                .font(.system(size: n == 1 ? 24 : (n == 2 ? 21 : 18), weight: .semibold, design: .serif))
                .foregroundStyle(Brand.ink)
                .padding(.top, 4)
        case .bullet(let m, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(m).font(Brand.serif).foregroundStyle(Brand.sub)
                Text(MD.attr(s)).font(Brand.serif).lineSpacing(5).foregroundStyle(Brand.ink)
            }
        case .quote(let s):
            HStack(spacing: 10) {
                Rectangle().fill(Brand.line).frame(width: 3)
                Text(MD.attr(s)).font(Brand.serif).foregroundStyle(Brand.sub)
            }
        case .code(let lang, let src):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(lang.isEmpty ? "代码" : lang).font(.caption).foregroundStyle(Brand.sub)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = src
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                    }
                    .foregroundStyle(Brand.sub)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(src).font(.system(size: 14, design: .monospaced)).foregroundStyle(Brand.ink).padding(12)
                }
            }
            .background(Brand.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .rule:
            Divider()
        }
    }
}
