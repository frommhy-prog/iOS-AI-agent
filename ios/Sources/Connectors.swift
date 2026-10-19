import Foundation
import UIKit

// 连接器：连接本机已有的 App（快捷指令、Scriptable、任意网址方案）或调用网络接口
enum Connectors {
    static func all() -> [Row] { DB.shared.rows("SELECT * FROM connector ORDER BY id") }

    static func add(name: String, kind: String, url: String, method: String = "GET", headers: String = "", body: String = "") {
        DB.shared.run("INSERT INTO connector(name,kind,url,method,headers,body) VALUES(?,?,?,?,?,?)", [name, kind, url, method, headers, body])
    }

    static func remove(_ id: Int) { DB.shared.run("DELETE FROM connector WHERE id=?", [id]) }

    static func kindName(_ k: String) -> String {
        switch k {
        case "shortcut": return "快捷指令"
        case "scriptable": return "Scriptable 脚本"
        case "url": return "其他 App"
        default: return "网络接口"
        }
    }

    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    static func run(_ name: String, _ input: String) async -> String {
        guard let c = all().first(where: { $0.s("name") == name }) else { return "没有找到名为「\(name)」的连接器" }
        let kind = c.s("kind")
        let target = c.s("url")
        var link = ""
        switch kind {
        case "shortcut": link = "shortcuts://run-shortcut?name=\(enc(target))&input=text&text=\(enc(input))"
        case "scriptable": link = "scriptable:///run?scriptName=\(enc(target))&input=\(enc(input))"
        case "url": link = target.replacingOccurrences(of: "{{input}}", with: enc(input))
        default:
            let urlStr = target.replacingOccurrences(of: "{{input}}", with: enc(input))
            guard let url = URL(string: urlStr) else { return "接口地址无效" }
            var req = URLRequest(url: url)
            req.httpMethod = c.s("method").isEmpty ? "GET" : c.s("method")
            req.timeoutInterval = 25
            for line in c.s("headers").split(separator: "\n") {
                let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { req.setValue(kv[1], forHTTPHeaderField: kv[0]) }
            }
            let body = c.s("body")
            if !body.isEmpty && req.httpMethod != "GET" {
                req.httpBody = body.replacingOccurrences(of: "{{input}}", with: input.replacingOccurrences(of: "\"", with: "\\\"")).data(using: .utf8)
                if req.value(forHTTPHeaderField: "Content-Type") == nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            }
            do {
                let (d, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let text = String(decoding: d.prefix(3000), as: UTF8.self)
                return code >= 400 ? "接口返回错误（\(code)）：\(text.prefix(200))" : text
            } catch {
                return "接口调用失败：\(error.localizedDescription)"
            }
        }
        guard let url = URL(string: link) else { return "目标地址无效" }
        let ok = await MainActor.run { () -> Bool in
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return true
        }
        return ok ? "已打开「\(name)」" : "无法打开，请确认对应 App 已安装"
    }
}
