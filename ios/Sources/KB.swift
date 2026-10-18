import Foundation
import NaturalLanguage
import Accelerate
import PDFKit

final class KB {
    static let shared = KB()
    private let emb = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
    var hasVector: Bool { emb != nil }
    static let textExt: Set<String> = ["txt", "md", "csv", "tsv", "json", "html", "htm", "xml", "log", "yaml", "yml", "swift", "js", "py", "rtf"]

    private func vec(_ s: String) -> [Float]? {
        guard let v = emb?.vector(for: s), !v.isEmpty else { return nil }
        let f = v.map { Float($0) }
        var n: Float = 0
        vDSP_svesq(f, 1, &n, vDSP_Length(f.count))
        let m = max(n.squareRoot(), 1e-6)
        return f.map { $0 / m }
    }

    private func grams(_ s: String) -> Set<String> {
        let c = Array(s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation })
        guard c.count > 1 else { return Set(c.map { String($0) }) }
        return Set((0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) })
    }

    private func chunks(_ t: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for line in t.components(separatedBy: .newlines) {
            let p = line.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            if cur.count + p.count > 300 {
                if !cur.isEmpty { out.append(cur) }
                cur = ""
            }
            var s = Substring(p)
            while s.count > 300 {
                out.append(String(s.prefix(300)))
                s = s.dropFirst(300)
            }
            cur += (cur.isEmpty ? "" : "\n") + String(s)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    func add(_ name: String, _ text: String) {
        let id = DB.shared.run("INSERT INTO doc(name,ts) VALUES(?,?)", [name, Date().timeIntervalSince1970])
        for c in chunks(text) {
            let b: Data? = vec(c).map { v in v.withUnsafeBytes { Data($0) } }
            DB.shared.run("INSERT INTO chunk(doc,text,vec) VALUES(?,?,?)", [id, c, b])
        }
    }

    func upsert(_ name: String, _ text: String) {
        DB.shared.run("DELETE FROM chunk WHERE doc IN (SELECT id FROM doc WHERE name=?)", [name])
        DB.shared.run("DELETE FROM doc WHERE name=?", [name])
        add(name, text)
    }

    func delete(_ id: Int) {
        DB.shared.run("DELETE FROM chunk WHERE doc=?", [id])
        DB.shared.run("DELETE FROM doc WHERE id=?", [id])
    }

    func docs() -> [Row] {
        DB.shared.rows("SELECT d.id AS id, d.name AS name, d.ts AS ts, (SELECT COUNT(*) FROM chunk c WHERE c.doc=d.id) AS n FROM doc d ORDER BY d.ts DESC")
    }

    func text(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return PDFDocument(url: url)?.string ?? "" }
        guard Self.textExt.contains(ext), let d = try? Data(contentsOf: url) else { return "" }
        if ext == "rtf", let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return a.string
        }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        var s = String(data: d, encoding: .utf8) ?? String(data: d, encoding: gb) ?? ""
        if ext == "html" || ext == "htm" {
            s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        return s
    }

    @discardableResult
    func ingest(_ url: URL) -> Int {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let t = text(of: url)
        if !t.isEmpty { upsert(url.lastPathComponent, t) }
        return t.count
    }

    func search(_ q: String, k: Int = 3) -> [String] {
        let rows = DB.shared.rows("SELECT text, vec FROM chunk")
        guard !rows.isEmpty else { return [] }
        let qg = grams(q)
        let qv = vec(q)
        var scored: [(Double, String)] = []
        for r in rows {
            let t = r.s("text")
            var sc = 0.0
            if !qg.isEmpty { sc = Double(qg.intersection(grams(t)).count) / Double(qg.count) }
            if let qv, let d = r["vec"] as? Data, d.count == qv.count * 4 {
                let v = d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                var dot: Float = 0
                vDSP_dotpr(qv, 1, v, 1, &dot, vDSP_Length(v.count))
                sc = sc * 0.6 + Double(max(dot, 0)) * 0.4
            }
            if sc > 0.12 { scored.append((sc, t)) }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(k).map { $0.1 }
    }
}
