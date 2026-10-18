import Foundation
import UIKit
import PDFKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// 文件格式互转：图片 / PDF / 文本 / 表格 / 视频
enum Convert {
    static let imgExt = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
    static let vidExt = ["mp4", "mov", "m4v"]

    static func err(_ s: String) -> NSError { NSError(domain: "转换", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }

    static func out(_ base: String, _ ext: String) -> URL {
        Store.dir("Outputs").appendingPathComponent(base + "-" + String(Int(Date().timeIntervalSince1970) % 100000) + "." + ext)
    }

    static func normalize(_ s: String) -> String {
        let t = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let m = ["jpeg": "jpg", "压缩": "compress", "音频": "m4a", "mp3": "m4a", "文本": "txt", "文字": "txt", "表格": "csv",
                 "markdown": "md", "网页": "html", "图片": "png", "视频": "mp4", "heif": "heic", "tif": "tiff"]
        return m[t] ?? t
    }

    static func run(_ src: URL, to target: String) async throws -> [URL] {
        let ext = src.pathExtension.lowercased()
        let t = normalize(target)
        let base = src.deletingPathExtension().lastPathComponent
        if imgExt.contains(ext) { return try image(src, base, t) }
        if ext == "pdf" { return try pdf(src, base, t) }
        if vidExt.contains(ext) { return [try await video(src, base, t)] }
        if KB.textExt.contains(ext) { return [try await doc(src, base, ext, t)] }
        throw err("暂不支持 .\(ext) 转 .\(t)")
    }

    // MARK: 图片
    static func image(_ src: URL, _ base: String, _ t: String) throws -> [URL] {
        guard let img = UIImage(contentsOfFile: src.path) else { throw err("无法读取图片") }
        let dst = out(base, t)
        switch t {
        case "pdf":
            let r = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: img.size))
            try r.writePDF(to: dst) { c in
                c.beginPage()
                img.draw(at: .zero)
            }
        case "jpg":
            guard let d = img.jpegData(compressionQuality: 0.9) else { throw err("编码失败") }
            try d.write(to: dst)
        case "png":
            guard let d = img.pngData() else { throw err("编码失败") }
            try d.write(to: dst)
        case "heic", "tiff", "gif", "bmp":
            let types: [String: UTType] = ["heic": .heic, "tiff": .tiff, "gif": .gif, "bmp": .bmp]
            guard let ty = types[t], let cg = img.cgImage,
                  let dest = CGImageDestinationCreateWithURL(dst as CFURL, ty.identifier as CFString, 1, nil) else { throw err("不支持写入 \(t)") }
            CGImageDestinationAddImage(dest, cg, nil)
            guard CGImageDestinationFinalize(dest) else { throw err("编码失败") }
        case "txt":
            let text = OCR.text(src)
            if text.isEmpty { throw err("没有识别到文字") }
            try text.write(to: dst, atomically: true, encoding: .utf8)
        default:
            throw err("图片不能转成 \(t)")
        }
        return [dst]
    }

    // MARK: PDF
    static func pdf(_ src: URL, _ base: String, _ t: String) throws -> [URL] {
        guard let doc = PDFDocument(url: src) else { throw err("无法打开 PDF") }
        if t == "txt" {
            let d = out(base, "txt")
            try (doc.string ?? "").write(to: d, atomically: true, encoding: .utf8)
            return [d]
        }
        guard t == "png" || t == "jpg" else { throw err("PDF 可转成 png、jpg、txt") }
        var outs: [URL] = []
        for i in 0..<min(doc.pageCount, 20) {
            guard let p = doc.page(at: i) else { continue }
            let sz = p.bounds(for: .mediaBox).size
            let img = p.thumbnail(of: CGSize(width: sz.width * 2, height: sz.height * 2), for: .mediaBox)
            let d = out("\(base)-p\(i + 1)", t)
            let data = t == "png" ? img.pngData() : img.jpegData(compressionQuality: 0.9)
            try data?.write(to: d)
            outs.append(d)
        }
        return outs
    }

    // MARK: 视频
    static func video(_ src: URL, _ base: String, _ t: String) async throws -> URL {
        let asset = AVURLAsset(url: src)
        if t == "jpg" || t == "png" {
            let g = AVAssetImageGenerator(asset: asset)
            g.appliesPreferredTrackTransform = true
            let (cg, _) = try await g.image(at: .zero)
            let img = UIImage(cgImage: cg)
            let d = out(base, t)
            try (t == "png" ? img.pngData() : img.jpegData(compressionQuality: 0.9))?.write(to: d)
            return d
        }
        let preset: String
        let type: AVFileType
        let ext: String
        switch t {
        case "m4a": preset = AVAssetExportPresetAppleM4A; type = .m4a; ext = "m4a"
        case "mov": preset = AVAssetExportPresetHighestQuality; type = .mov; ext = "mov"
        case "compress": preset = AVAssetExportPreset1280x720; type = .mp4; ext = "mp4"
        case "mp4": preset = AVAssetExportPresetHighestQuality; type = .mp4; ext = "mp4"
        default: throw err("视频可转成 mp4、mov、m4a、jpg 或 压缩")
        }
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else { throw err("无法创建导出任务") }
        let dst = out(base, ext)
        try await s.export(to: dst, as: type)
        return dst
    }

    // MARK: 文本与表格
    static func doc(_ src: URL, _ base: String, _ ext: String, _ t: String) async throws -> URL {
        let raw = KB.shared.text(of: src)
        guard !raw.isEmpty else { throw err("文件为空或无法读取") }
        var content = raw
        let tableSrc = ["csv", "tsv", "json"].contains(ext) || (ext == "md" && raw.contains("|"))
        if tableSrc || ["csv", "tsv", "json"].contains(t) {
            let rows: [[String]]
            switch ext {
            case "json": rows = jsonRows(raw)
            case "md": rows = mdRows(raw)
            case "csv": rows = csvParse(raw, ",")
            default: rows = csvParse(raw, "\t")
            }
            guard !rows.isEmpty else { throw err("没有识别到表格") }
            switch t {
            case "csv": content = csvOut(rows, ",")
            case "tsv", "txt", "pdf": content = csvOut(rows, "\t")
            case "json": content = jsonOut(rows)
            case "md": content = mdOut(rows)
            case "html": content = "<meta charset=utf-8><table border=1>" + rows.map { r in "<tr>" + r.map { c in "<td>\(c)</td>" }.joined() + "</tr>" }.joined() + "</table>"
            default: throw err("表格可转成 csv、json、md、html、tsv、txt、pdf")
            }
        } else if t == "html" {
            content = "<meta charset=utf-8><pre style='white-space:pre-wrap'>" + raw + "</pre>"
        } else if !["txt", "md", "pdf"].contains(t) {
            throw err("文本可转成 txt、md、html、pdf")
        }
        let dst = out(base, t)
        if t == "pdf" {
            try await MainActor.run { try textPDF(content, dst) }
        } else {
            try content.write(to: dst, atomically: true, encoding: .utf8)
        }
        return dst
    }

    static func textPDF(_ text: String, _ dst: URL) throws {
        let fmt = UISimpleTextPrintFormatter(text: text)
        fmt.font = UIFont.systemFont(ofSize: 12)
        let r = UIPrintPageRenderer()
        r.addPrintFormatter(fmt, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        r.setValue(page, forKey: "paperRect")
        r.setValue(page.insetBy(dx: 36, dy: 36), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for i in 0..<r.numberOfPages {
            UIGraphicsBeginPDFPage()
            r.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        try (data as Data).write(to: dst)
    }

    static func csvParse(_ s: String, _ delim: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cur = ""
        var q = false
        let cs = Array(s)
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if q {
                if c == "\"" {
                    if i + 1 < cs.count && cs[i + 1] == "\"" { cur.append("\""); i += 1 } else { q = false }
                } else { cur.append(c) }
            } else if c == "\"" { q = true }
            else if c == delim { row.append(cur); cur = "" }
            else if c.isNewline { row.append(cur); cur = ""; rows.append(row); row = [] }
            else { cur.append(c) }
            i += 1
        }
        if !cur.isEmpty || !row.isEmpty { row.append(cur); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    static func jsonRows(_ s: String) -> [[String]] {
        guard let d = s.data(using: .utf8),
              let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]], !a.isEmpty else { return [] }
        let keys = Array(Set(a.flatMap { $0.keys })).sorted()
        return [keys] + a.map { o in keys.map { k in o[k].map { "\($0)" } ?? "" } }
    }

    static func mdRows(_ s: String) -> [[String]] {
        s.split(separator: "\n").map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
            .filter { !$0.replacingOccurrences(of: "[|:\\-\\s]", with: "", options: .regularExpression).isEmpty }
            .map { line in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                return Array(parts.dropFirst().dropLast())
            }
    }

    static func csvOut(_ rows: [[String]], _ d: String) -> String {
        rows.map { r in
            r.map { c in
                (c.contains(d) || c.contains("\"") || c.contains("\n")) ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c
            }.joined(separator: d)
        }.joined(separator: "\n")
    }

    static func mdOut(_ rows: [[String]]) -> String {
        guard let h = rows.first else { return "" }
        var l = ["| " + h.joined(separator: " | ") + " |", "|" + h.map { _ in " --- |" }.joined()]
        for r in rows.dropFirst() { l.append("| " + r.joined(separator: " | ") + " |") }
        return l.joined(separator: "\n")
    }

    static func jsonOut(_ rows: [[String]]) -> String {
        guard let h = rows.first else { return "[]" }
        let arr: [[String: String]] = rows.dropFirst().map { r in
            var o: [String: String] = [:]
            for (i, k) in h.enumerated() { o[k] = i < r.count ? r[i] : "" }
            return o
        }
        let d = (try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])) ?? Data()
        return String(decoding: d, as: UTF8.self)
    }
}
